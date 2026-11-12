import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/constants.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../models/reception.dart';
import 'format.dart';

/// 엑셀에서 열 수 있는 CSV 만들기 (프로 전용).
/// 행사마다 제목 줄 → 열 제목 → 손님 한 줄씩(가나다순) → 합계 · 소계, 행사 사이는 빈 줄.
class CsvService {
  static const header = ['번호', '이름', '관계', '구분', '금액', '결제 방법', '식권', '메모', '날짜'];

  /// [records]: 모든 기록(사람 이름 · 관계 포함), [events]: 모든 행사,
  /// [receptions]: 내 행사로 아직 옮기지 않은 대신 받은 장부.
  /// 금액은 쉼표 없는 숫자, 엑셀에서 한글이 깨지지 않도록 UTF-8 BOM을 붙인다.
  /// 쉼표 · 따옴표 · 줄바꿈이 들어간 값은 큰따옴표로 감싼다.
  static String buildCsv({
    required List<GiftRecord> records,
    required List<Event> events,
    List<ReceptionPackage> receptions = const [],
    DateTime? today,
  }) {
    final rows = <List<Object>>[
      ['경조사 장부 내보내기', toDbDate(today ?? DateTime.now())],
    ];

    // 행사별 (날짜 최신순)
    final byEvent = <int, List<GiftRecord>>{};
    for (final r in records) {
      if (r.eventId != null) byEvent.putIfAbsent(r.eventId!, () => []).add(r);
    }
    final sortedEvents = [
      for (final e in events)
        if (byEvent.containsKey(e.id)) e,
    ]..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : (b.id ?? 0).compareTo(a.id ?? 0);
      });
    for (final e in sortedEvents) {
      rows
        ..add([])
        ..add(['[행사] ${e.title}', toDbDate(e.date), e.type, e.isMine ? '받음' : '보냄'])
        ..addAll(_section([for (final r in byEvent[e.id]!) _Row.fromRecord(r)]));
    }

    // 내 행사로 옮기지 않은 대신 받은 장부
    for (final pkg in receptions) {
      final r = pkg.reception;
      if (pkg.entries.isEmpty) continue;
      rows
        ..add([])
        ..add(['[대신 받은 장부] ${r.title}', toDbDate(r.date), r.eventType, '받음'])
        ..addAll(_section([
          for (final e in pkg.entries)
            _Row(
              name: e.name,
              relation: '',
              side: e.side == ReceptionDefaults.noSide ? '' : e.side,
              amount: e.amount,
              method: e.method,
              meals: r.mealTicketEnabled ? e.mealTickets : null,
              memo: e.memo ?? '',
              date: r.date,
              order: e.createdAt.millisecondsSinceEpoch,
            ),
        ]));
    }

    // 행사 없이 기록한 내역 (보냄 · 받음을 나눠서)
    final loose = [for (final r in records) if (r.eventId == null) r];
    for (final direction in [Direction.sent, Direction.received]) {
      final part = [for (final r in loose) if (r.direction == direction) _Row.fromRecord(r)];
      if (part.isEmpty) continue;
      rows
        ..add([])
        ..add(['[행사 없이 기록한 내역]', '', '', direction])
        ..addAll(_section(part));
    }

    // 전체 합계 (기록 기준)
    String total(String direction) {
      final part = records.where((r) => r.direction == direction);
      return '$direction ${part.length}건 ${part.fold(0, (s, r) => s + r.amount)}';
    }

    rows
      ..add([])
      ..add(['[전체 합계]', total(Direction.sent), total(Direction.received)]);
    return Csv(addBom: true).encode(rows);
  }

  /// 열 제목 → 손님 줄(가나다순) → 합계 · 구분별 소계 · 결제 방법별 합계
  static List<List<Object>> _section(List<_Row> list) {
    list.sort((a, b) {
      final c = a.name.compareTo(b.name);
      return c != 0 ? c : a.order.compareTo(b.order);
    });
    int sum(Iterable<_Row> rows) => rows.fold(0, (s, r) => s + r.amount);
    Object meals(Iterable<_Row> rows) {
      final known = rows.where((r) => r.meals != null);
      return known.isEmpty ? '' : known.fold<int>(0, (s, r) => s + r.meals!);
    }

    final out = <List<Object>>[
      header,
      for (var i = 0; i < list.length; i++)
        [
          i + 1,
          list[i].name,
          list[i].relation,
          list[i].side,
          list[i].amount,
          list[i].method,
          list[i].meals ?? '',
          list[i].memo,
          toDbDate(list[i].date),
        ],
      ['합계', '${list.length}명', '', '', sum(list), '', meals(list), '', ''],
    ];
    final sides = <String>[];
    for (final r in list) {
      if (r.side.isNotEmpty && !sides.contains(r.side)) sides.add(r.side);
    }
    for (final side in sides) {
      final part = list.where((r) => r.side == side);
      out.add(['$side 소계', '${part.length}명', '', '', sum(part), '', meals(part), '', '']);
    }
    // 현금 · 계좌가 섞여 있을 때만 결제 방법별 합계 (한 가지뿐이면 합계 줄과 같다)
    if (list.map((r) => r.method).toSet().length > 1) {
      for (final m in Methods.all) {
        final part = list.where((r) => r.method == m);
        if (part.isEmpty) continue;
        out.add(['$m 합계', '', '', '', sum(part), '', '', '', '']);
      }
    }
    return out;
  }

  static Future<void> exportAndShare({
    required List<GiftRecord> records,
    required List<Event> events,
    List<ReceptionPackage> receptions = const [],
  }) async {
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final file = File(p.join(dir.path, '경조사장부_내보내기_${toDbDate(now)}.csv'));
    await file.writeAsString(
        buildCsv(records: records, events: events, receptions: receptions, today: now),
        flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: '경조사 장부 내역 (엑셀)',
    ));
  }
}

/// CSV 한 줄의 재료
class _Row {
  const _Row({
    required this.name,
    required this.relation,
    required this.side,
    required this.amount,
    required this.method,
    required this.meals,
    required this.memo,
    required this.date,
    required this.order,
  });

  factory _Row.fromRecord(GiftRecord r) => _Row(
        name: r.personName ?? '',
        relation: r.personRelation ?? '',
        side: r.side ?? '',
        amount: r.amount,
        method: r.method,
        meals: r.mealTickets,
        memo: r.memo ?? '',
        date: r.date,
        order: r.id ?? 0,
      );

  final String name;
  final String relation;
  final String side;
  final int amount;
  final String method;
  final int? meals;
  final String memo;
  final DateTime date;

  /// 같은 이름끼리의 순서 (받은 순서)
  final int order;
}
