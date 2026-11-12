import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../models/person.dart';
import '../models/reception.dart';
import 'limit_service.dart';
import 'settings_service.dart';

/// 받은 돈 적기 화면의 한 줄 (내 행사 기록 또는 대신 받은 항목)
class ReceiveItem {
  const ReceiveItem({
    required this.id,
    required this.name,
    required this.amount,
    required this.side,
    required this.method,
    required this.mealTickets,
    required this.source,
    this.savedAt,
  });
  final Object id;
  final String name;
  final int amount;
  final String side;
  final String method;
  final int mealTickets;

  /// 저장 시각. 예전에 적은 내 행사 기록은 시각이 없다.
  final DateTime? savedAt;

  /// 원래 데이터 ([GiftRecord] 또는 [ReceptionEntry]). 수정 · 되돌리기에 쓴다.
  final Object source;
}

/// 받은 돈 적기 화면이 보여줄 지금 상태
class ReceiveSnapshot {
  const ReceiveSnapshot({
    required this.title,
    required this.sides,
    required this.mealTicketEnabled,
    required this.defaultMealTickets,
    required this.methodEnabled,
    required this.items,
  });
  final String title;
  final List<String> sides;
  final bool mealTicketEnabled;
  final int defaultMealTickets;
  final bool methodEnabled;

  /// 최신이 앞
  final List<ReceiveItem> items;

  int get count => items.length;
  int get total => items.fold(0, (s, e) => s + e.amount);

  /// 설정한 구분 + 항목에만 있는 구분
  List<String> get allSides => {...sides, ...items.map((e) => e.side)}.toList();

  ({int count, int amount}) totalsFor(String side) {
    final list = items.where((e) => e.side == side);
    return (count: list.length, amount: list.fold(0, (s, e) => s + e.amount));
  }
}

/// 저장할 한 건
class ReceiveInput {
  const ReceiveInput({
    required this.name,
    required this.amount,
    required this.side,
    required this.transfer,
    required this.mealTickets,
    this.person,
  });
  final String name;
  final int amount;
  final String side;
  final bool transfer;

  /// 식권 기록을 끈 경우 null
  final int? mealTickets;

  /// 내 행사에서 자동완성으로 고른 기존 사람
  final Person? person;
}

/// 받은 돈 적기 화면의 저장 위치. 화면은 하나이고 저장하는 부분만 다르다.
/// - [MyEventTarget]: 내 행사 → people + records('받음'), 무료 30명 한도 적용
/// - [ReceptionTarget]: 다른 사람 행사(대신 받기) → receptions + reception_entries, 결제 화면 없음
sealed class ReceiveTarget {
  const ReceiveTarget();

  /// 현황 줄 옆의 저장 위치 이름
  String get placeLabel;
  bool get isMine;
  String get sidePrefKey;

  /// 지금 상태. 처음 읽는 중이면 null. 저장 뒤 새로 읽는 동안에는 전 상태를 그대로 준다
  /// (화면이 잠깐 비지 않게).
  ReceiveSnapshot? watch(WidgetRef ref);

  /// 저장했으면 true. 내 행사에서 31번째 새 사람의 결제 화면을 닫으면 false.
  Future<bool> save(BuildContext context, WidgetRef ref, ReceiveInput input);

  Future<void> undo(WidgetRef ref, ReceiveItem item);

  /// 현황 줄의 식권 켜기 · 끄기. 이미 저장한 항목은 그대로 둔다.
  Future<void> setMealTicketEnabled(WidgetRef ref, bool enabled);
}

class MyEventTarget extends ReceiveTarget {
  const MyEventTarget(this.eventId);
  final int eventId;

  @override
  String get placeLabel => '내 행사';
  @override
  bool get isMine => true;
  @override
  String get sidePrefKey => PrefKeys.eventLastSide(eventId);

  @override
  ReceiveSnapshot? watch(WidgetRef ref) {
    final d = ref.watch(eventDetailProvider(eventId)).value;
    return d == null ? null : snapshotOf(d.event, d.mainRecords);
  }

  /// 내 행사 기록을 화면 상태로 바꾼다. 기록은 최신이 앞(id 내림차순).
  static ReceiveSnapshot snapshotOf(Event event, List<GiftRecord> records) =>
      ReceiveSnapshot(
        title: event.title,
        sides: event.sides,
        mealTicketEnabled: event.mealTicketEnabled,
        defaultMealTickets: event.defaultMealTickets,
        methodEnabled: event.methodEnabled,
        items: [
          for (final r in records)
            ReceiveItem(
              id: r.id ?? 0,
              name: r.personName ?? '',
              amount: r.amount,
              side: r.side ?? ReceptionDefaults.noSide,
              method: r.method,
              mealTickets: r.mealTickets ?? 0,
              savedAt: _savedAt[r.id],
              source: r,
            ),
        ],
      );

  /// 이번 실행에서 저장한 기록의 시각 (기록에는 날짜만 있어서 따로 기억한다)
  static final _savedAt = <int?, DateTime>{};

  @override
  Future<bool> save(
      BuildContext context, WidgetRef ref, ReceiveInput input) async {
    final repo = ref.read(repositoryProvider);
    final event = await repo.getEvent(eventId);
    if (event == null) return false;

    // 사람 찾기: 자동완성 선택 > 같은 이름 > 새로 등록
    var person = input.person;
    if (person == null) {
      final same = await repo.findPeopleByExactName(input.name);
      if (same.isNotEmpty) person = same.first;
    }
    if (person == null) {
      if (!context.mounted) return false;
      // 31번째 새 사람부터 결제 화면. 닫으면 적은 이름 · 금액을 그대로 두고 돌아간다.
      if (!await LimitService.canAddNewPerson(context, ref)) return false;
      final id = await repo.insertPerson(Person(
        name: input.name,
        relation:
            ref.read(prefsProvider).getString(PrefKeys.quickEntryRelation) ??
                '지인',
        createdAt: DateTime.now(),
      ));
      person = Person(id: id, name: input.name, createdAt: DateTime.now());
    }
    final recordId = await repo.insertRecord(GiftRecord(
      personId: person.id!,
      eventId: eventId,
      direction: Direction.received,
      amount: input.amount,
      method: input.transfer ? ReceptionDefaults.transfer : ReceptionDefaults.cash,
      date: event.date,
      side: input.side == ReceptionDefaults.noSide ? null : input.side,
      mealTickets: input.mealTickets,
    ));
    _savedAt[recordId] = DateTime.now();
    ref.refreshData();
    return true;
  }

  @override
  Future<void> undo(WidgetRef ref, ReceiveItem item) async {
    await ref.read(repositoryProvider).deleteRecord(item.id as int);
    ref.refreshData();
  }

  @override
  Future<void> setMealTicketEnabled(WidgetRef ref, bool enabled) async {
    await ref.read(repositoryProvider).setEventMealTicketEnabled(eventId, enabled);
    ref.refreshData();
  }
}

class ReceptionTarget extends ReceiveTarget {
  const ReceptionTarget(this.receptionId);
  final String receptionId;

  @override
  String get placeLabel => '대신 받기';
  @override
  bool get isMine => false;
  @override
  String get sidePrefKey => PrefKeys.receptionLastSide(receptionId);

  @override
  ReceiveSnapshot? watch(WidgetRef ref) {
    final p = ref.watch(receptionPackageProvider(receptionId)).value;
    return p == null ? null : snapshotOf(p);
  }

  static ReceiveSnapshot snapshotOf(ReceptionPackage p) {
    final r = p.reception;
    return ReceiveSnapshot(
      title: r.title,
      sides: r.sides,
      mealTicketEnabled: r.mealTicketEnabled,
      defaultMealTickets: r.defaultMealTickets,
      methodEnabled: r.methodEnabled,
      items: [
        for (final e in p.entries)
          ReceiveItem(
            id: e.id,
            name: e.name,
            amount: e.amount,
            side: e.side,
            method: e.method,
            mealTickets: e.mealTickets,
            savedAt: e.createdAt,
            source: e,
          ),
      ],
    );
  }

  /// 대신 받기는 사람 목록에 넣지 않으므로 한도 검사도, 결제 화면도 없다.
  @override
  Future<bool> save(
      BuildContext context, WidgetRef ref, ReceiveInput input) async {
    await ref.read(repositoryProvider).insertReceptionEntry(ReceptionEntry(
          id: const Uuid().v4(),
          receptionId: receptionId,
          name: input.name,
          amount: input.amount,
          side: input.side,
          method: input.transfer
              ? ReceptionDefaults.transfer
              : ReceptionDefaults.cash,
          mealTickets: input.mealTickets ?? 0,
          createdAt: DateTime.now(),
        ));
    ref.refreshData();
    return true;
  }

  @override
  Future<void> undo(WidgetRef ref, ReceiveItem item) async {
    await ref.read(repositoryProvider).deleteReceptionEntry(item.id as String);
    ref.refreshData();
  }

  @override
  Future<void> setMealTicketEnabled(WidgetRef ref, bool enabled) async {
    await ref
        .read(repositoryProvider)
        .setReceptionMealTicketEnabled(receptionId, enabled);
    ref.refreshData();
  }
}
