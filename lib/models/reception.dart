import 'dart:convert';

import '../services/format.dart';
import 'constants.dart';

/// 다른 사람 행사 장부 1개. 접수 명단은 people 테이블과 분리되어 무료 한도에 걸리지 않는다.
class Reception {
  final String id;
  final String title;
  final String eventType;
  final DateTime date;
  final List<String> sides;
  final String operatorName;
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// 식권을 기록하는지, 기록한다면 기본 몇 매인지
  final bool mealTicketEnabled;
  final int defaultMealTickets;

  /// 현금과 계좌이체를 구분하는지
  final bool methodEnabled;

  /// 내 장부로 모두 옮겼는지
  final bool imported;

  const Reception({
    required this.id,
    required this.title,
    required this.eventType,
    required this.date,
    required this.sides,
    required this.operatorName,
    required this.startedAt,
    this.finishedAt,
    this.mealTicketEnabled = true,
    this.defaultMealTickets = 1,
    this.methodEnabled = true,
    this.imported = false,
  });

  /// 접수 중에 식권 기록을 켜거나 끌 때 쓴다.
  Reception copyWith({bool? mealTicketEnabled}) => Reception(
        id: id,
        title: title,
        eventType: eventType,
        date: date,
        sides: sides,
        operatorName: operatorName,
        startedAt: startedAt,
        finishedAt: finishedAt,
        mealTicketEnabled: mealTicketEnabled ?? this.mealTicketEnabled,
        defaultMealTickets: defaultMealTickets,
        methodEnabled: methodEnabled,
        imported: imported,
      );

  bool get isFinished => finishedAt != null;

  factory Reception.fromMap(Map<String, Object?> m) => Reception(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        eventType: (m['event_type'] as String?) ?? '기타',
        date: parseDbDate(m['date'] as String?),
        sides: _decodeSides(m['sides'] as String?),
        operatorName: (m['operator_name'] as String?) ?? '',
        startedAt: DateTime.tryParse(m['started_at'] as String? ?? '') ??
            DateTime.now(),
        finishedAt: DateTime.tryParse(m['finished_at'] as String? ?? ''),
        mealTicketEnabled: (m['meal_ticket_enabled'] as int? ?? 1) == 1,
        defaultMealTickets: m['default_meal_tickets'] as int? ?? 1,
        methodEnabled: (m['method_enabled'] as int? ?? 1) == 1,
        imported: (m['imported'] as int? ?? 0) == 1,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'event_type': eventType,
        'date': toDbDate(date),
        'sides': jsonEncode(sides),
        'operator_name': operatorName,
        'started_at': startedAt.toIso8601String(),
        'finished_at': finishedAt?.toIso8601String(),
        'meal_ticket_enabled': mealTicketEnabled ? 1 : 0,
        'default_meal_tickets': defaultMealTickets,
        'method_enabled': methodEnabled ? 1 : 0,
        'imported': imported ? 1 : 0,
      };

  static List<String> _decodeSides(String? raw) {
    if (raw == null || raw.isEmpty) return const [ReceptionDefaults.noSide];
    final list = (jsonDecode(raw) as List).whereType<String>().toList();
    return list.isEmpty ? const [ReceptionDefaults.noSide] : list;
  }
}

/// 접수 항목 1건 (손님 1명).
class ReceptionEntry {
  final String id;
  final String receptionId;
  final String name;
  final int amount;
  final String side;

  /// '현금' 또는 '계좌'
  final String method;
  final int mealTickets;
  final String? memo;
  final DateTime createdAt;

  /// 되돌리기/삭제한 항목은 지우지 않고 표시만 해 둔다.
  final bool deleted;

  const ReceptionEntry({
    required this.id,
    required this.receptionId,
    required this.name,
    required this.amount,
    required this.side,
    this.method = ReceptionDefaults.cash,
    this.mealTickets = 1,
    this.memo,
    required this.createdAt,
    this.deleted = false,
  });

  factory ReceptionEntry.fromMap(Map<String, Object?> m) => ReceptionEntry(
        id: m['id'] as String,
        receptionId: m['reception_id'] as String,
        name: (m['name'] as String?) ?? '',
        amount: m['amount'] as int? ?? 0,
        side: (m['side'] as String?) ?? '',
        method: (m['method'] as String?) ?? ReceptionDefaults.cash,
        mealTickets: m['meal_tickets'] as int? ?? 1,
        memo: m['memo'] as String?,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
            DateTime.now(),
        deleted: (m['deleted'] as int? ?? 0) == 1,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'reception_id': receptionId,
        'name': name,
        'amount': amount,
        'side': side,
        'method': method,
        'meal_tickets': mealTickets,
        'memo': memo,
        'created_at': createdAt.toIso8601String(),
        'deleted': deleted ? 1 : 0,
      };

  ReceptionEntry copyWith({
    String? name,
    int? amount,
    String? side,
    String? method,
    int? mealTickets,
    String? memo,
  }) =>
      ReceptionEntry(
        id: id,
        receptionId: receptionId,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        side: side ?? this.side,
        method: method ?? this.method,
        mealTickets: mealTickets ?? this.mealTickets,
        memo: memo,
        createdAt: createdAt,
        deleted: deleted,
      );
}

/// 구분별 또는 전체 합계
class ReceptionTotals {
  final int count;
  final int amount;
  final int mealTickets;

  const ReceptionTotals(
      {this.count = 0, this.amount = 0, this.mealTickets = 0});

  factory ReceptionTotals.of(Iterable<ReceptionEntry> entries) {
    var count = 0, amount = 0, meals = 0;
    for (final e in entries) {
      count++;
      amount += e.amount;
      meals += e.mealTickets;
    }
    return ReceptionTotals(count: count, amount: amount, mealTickets: meals);
  }
}

/// 다른 사람 행사 장부 + 항목. 장부 보내기의 단위이자 화면 표시용 묶음.
/// (예전 JSON 장부 파일 만들기 · 읽기는 v1에서 없앴다, 2026-11-27)
class ReceptionPackage {
  final Reception reception;
  final List<ReceptionEntry> entries;

  const ReceptionPackage(this.reception, this.entries);

  ReceptionTotals get totals => ReceptionTotals.of(entries);

  ReceptionTotals totalsFor(String side) =>
      ReceptionTotals.of(entries.where((e) => e.side == side));

  /// 현금 · 계좌 합계 (결제 방법을 구분한 접수에서 보여준다)
  ReceptionTotals totalsForMethod(String method) =>
      ReceptionTotals.of(entries.where((e) => e.method == method));

  /// 식권을 표시할지. 접수 중에 기록을 껐어도 이미 적은 식권은 보여준다.
  bool get showsMealTickets =>
      reception.mealTicketEnabled || totals.mealTickets > 0;

  /// 저장된 구분 + 항목에만 있는 구분 (수정 등으로 달라졌을 때도 빠지지 않게)
  List<String> get sides => {
        ...reception.sides,
        ...entries.map((e) => e.side),
      }.toList();
}

/// 장부 목록에 보여줄 다른 사람 행사 장부 요약
class ReceptionSummary {
  final Reception reception;
  final int count;
  final int total;
  const ReceptionSummary(this.reception, this.count, this.total);
}
