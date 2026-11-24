import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models/constants.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../models/person.dart';
import '../models/reception.dart';
import 'format.dart';
import 'ledger_text_format.dart';
import 'reminder_format.dart';

/// 엑셀 파일(.xlsx) 만들기 (무료). 두 가지를 만든다.
/// ① 행사 장부: [명단] [합계] 시트 (내 행사 · 다른 사람 행사 모두)
/// ② 주고받은 내역(홈): [내역] [사람별 합계] [행사 일정] 시트
/// 두 파일 모두 숨긴 [정보] 시트에 파일 종류와 형식 버전을 넣어, 나중에 엑셀 가져오기에서 쓸 수 있게 한다.
/// 앱에 저장된 값은 빠짐없이 넣고(내부 id 제외), 값이 없는 열도 빈칸으로 남겨 열 위치를 늘 같게 둔다.
/// 금액은 숫자 칸 + 천 단위 쉼표, 합계는 수식이 아니라 앱에서 계산한 값(폰 뷰어에서도 보이게).
class ExportService {
  static const formatVersion = 1;
  static const appName = '경조사 장부';
  static const kindLedger = '장부';
  static const kindHistory = '주고받은 내역';
  static const kindAllEvents = '행사 전체';

  /// 파일 이름에 쓸 수 없는 글자를 '_'로 바꾼다.
  static String safeFileName(String name) =>
      name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();

  static String _yyyymmdd(DateTime d) => DateFormat('yyyyMMdd').format(d);

  /// 경조사장부_{행사이름}_{행사날짜}.xlsx (텍스트는 [ext] = 'txt')
  static String ledgerFileName(String title, DateTime date, {String ext = 'xlsx'}) =>
      safeFileName('경조사장부_${title}_${_yyyymmdd(date)}.$ext');

  /// 경조사장부_행사전체_{오늘}.xlsx
  static String allEventsFileName(DateTime today, {String ext = 'xlsx'}) =>
      safeFileName('경조사장부_행사전체_${_yyyymmdd(today)}.$ext');

  /// 경조사장부_주고받은내역_{오늘}.xlsx
  static String historyFileName(DateTime today, {String ext = 'xlsx'}) =>
      safeFileName('경조사장부_주고받은내역_${_yyyymmdd(today)}.$ext');

  // ───────────────────────── ① 행사 장부 ─────────────────────────

  static const ledgerHeader = [
    '번호', '이름', '금액', '구분', '결제 방법', '식권', '메모', '적은 날짜', '시간',
    // 기획서 목록에는 없지만 앱에 저장된 값 (내 행사 손님만 값이 있음)
    '관계', '연락처', '확인 필요',
  ];

  static Uint8List buildLedger(LedgerExcel ledger, {DateTime? now}) {
    final book = _Book();
    final list = book.sheet('명단');
    _writeInfo(list, ledger, 0); // 1~2행: 행사 정보
    _writeList(list, ledger, 3); // 4행: 열 제목, 5행부터 손님
    list.freezeRows = 4;
    final sum = book.sheet('합계');
    _writeTotals(sum, ledger, 0);
    sum.freezeRows = 1;
    book.info(kindLedger, now ?? DateTime.now());
    return book.encode();
  }

  /// [row]행에 제목, 다음 행에 값 (값이 있는 것만)
  static void _writeInfo(_Sheet sheet, LedgerExcel ledger, int row) {
    final info = [
      for (final (label, value) in ledger.info)
        if (value.trim().isNotEmpty) (label, value),
    ];
    for (var i = 0; i < info.length; i++) {
      sheet.text(row, i, info[i].$1, bold: true);
      sheet.text(row + 1, i, info[i].$2);
    }
  }

  /// [headerRow]행에 열 제목, 그 아래 손님 줄. 다음 빈 행 번호를 돌려준다.
  static int _writeList(_Sheet sheet, LedgerExcel ledger, int headerRow) {
    sheet.header(headerRow, ledgerHeader);
    final rows = ledger.rows;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final row = headerRow + 1 + i;
      sheet
        ..number(row, 0, i + 1, money: false)
        ..text(row, 1, r.name)
        ..number(row, 2, r.amount)
        ..text(row, 3, r.side)
        ..text(row, 4, r.method)
        ..intOrBlank(row, 5, r.mealTickets)
        ..text(row, 6, r.memo)
        ..text(row, 7, toDbDate(r.date))
        ..text(row, 8, r.time == null ? '' : DateFormat('HH:mm').format(r.time!))
        ..text(row, 9, r.relation)
        ..text(row, 10, r.phone)
        ..text(row, 11, r.needsReview ? '확인 필요' : '');
    }
    return headerRow + 1 + rows.length;
  }

  /// 합계 표: 총계 → 구분별 → 결제 방법별 (열: 항목 · 인원 · 금액 · 식권)
  static void _writeTotals(_Sheet sheet, LedgerExcel ledger, int startRow) {
    final rows = ledger.rows;
    sheet.header(startRow, const ['항목', '인원', '금액', '식권']);
    var row = startRow + 1;
    void line(String label, Iterable<LedgerExcelRow> part, {bool meals = true}) {
      sheet
        ..text(row, 0, label)
        ..number(row, 1, part.length, money: false)
        ..number(row, 2, part.fold(0, (s, r) => s + r.amount));
      final known = part.where((r) => r.mealTickets != null);
      if (meals && known.isNotEmpty) {
        sheet.number(row, 3, known.fold(0, (s, r) => s + r.mealTickets!), money: false);
      }
      row++;
    }

    line('총계', rows);
    // 행사에 정한 구분은 0명이어도 앱 화면처럼 보여준다
    final sides = [...ledger.sides];
    for (final r in rows) {
      if (r.side.isNotEmpty && !sides.contains(r.side)) sides.add(r.side);
    }
    for (final side in sides) {
      line(side, rows.where((r) => r.side == side));
    }
    final methods = <String>[];
    for (final r in rows) {
      if (r.method.isNotEmpty && !methods.contains(r.method)) methods.add(r.method);
    }
    for (final m in methods) {
      line(m, rows.where((r) => r.method == m), meals: false);
    }
  }

  // ───────────────────────── ② 행사 전체 (행사 탭) ─────────────────────────

  static const eventListHeader = [
    '행사 이름', '종류', '날짜', '내/다른 사람 행사', '인원', '총액', '식권', '장소', '메모',
  ];

  /// [행사 목록] 시트(날짜 최신순) + 행사마다 시트 하나(위 행사 정보 → 명단 → 아래 합계)
  static Uint8List buildAllEvents(List<LedgerExcel> ledgers, {DateTime? now}) {
    final book = _Book();
    final sorted = [...ledgers]..sort((a, b) => b.date.compareTo(a.date));
    final index = book.sheet('행사 목록');
    index.header(0, eventListHeader);
    for (var i = 0; i < sorted.length; i++) {
      final l = sorted[i];
      final known = l.rows.where((r) => r.mealTickets != null);
      final row = 1 + i;
      index
        ..text(row, 0, l.title)
        ..text(row, 1, l.type)
        ..text(row, 2, toDbDate(l.date))
        ..text(row, 3, l.isMine ? '내 행사' : '다른 사람 행사')
        ..number(row, 4, l.rows.length, money: false)
        ..number(row, 5, l.rows.fold(0, (s, r) => s + r.amount));
      known.isEmpty
          ? index.text(row, 6, '')
          : index.number(row, 6, known.fold(0, (s, r) => s + r.mealTickets!),
              money: false);
      index
        ..text(row, 7, l.place)
        ..text(row, 8, l.memo);
    }
    index.freezeRows = 1;

    final used = {'행사 목록', '정보'};
    for (final l in sorted) {
      final sheet = book.sheet(uniqueSheetName(l.title, used));
      _writeInfo(sheet, l, 0);
      final next = _writeList(sheet, l, 3);
      _writeTotals(sheet, l, next + 1);
      sheet.freezeRows = 4;
    }
    book.info(kindAllEvents, now ?? DateTime.now());
    return book.encode();
  }

  /// 엑셀 시트 이름: [ ] : * ? / \ 를 빼고 31자까지, 같은 이름은 (2) (3)…
  static String uniqueSheetName(String title, Set<String> used) {
    var base = title.replaceAll(RegExp(r'[\[\]:*?/\\]'), '').trim();
    if (base.isEmpty) base = '행사';
    String cut(String s, int max) =>
        s.runes.length <= max ? s : String.fromCharCodes(s.runes.take(max));
    var name = cut(base, 31);
    for (var n = 2; used.contains(name); n++) {
      final suffix = '($n)';
      name = cut(base, 31 - suffix.length) + suffix;
    }
    used.add(name);
    return name;
  }

  // ───────────────────────── 텍스트 ─────────────────────────

  /// 행사 전체 공유: 행사마다 메시지 하나(100명이 넘는 행사만 나눔). 붙여넣어 가져오기와 같은 형식.
  static List<String> allEventsTextParts(List<ReceptionPackage> packages) => [
        for (final p in packages) ...LedgerText.build(p),
      ];

  /// 행사 하나 · 행사 전체 다운로드: 나누지 않고 .txt 하나 (행사 사이는 빈 줄)
  static String ledgersTextFile(List<ReceptionPackage> packages) => [
        for (final p in packages) LedgerText.build(p, chunkSize: 1 << 30).single,
      ].join('\n\n');

  /// 주고받은 내역 텍스트. [chunkSize]줄을 넘으면 나눠서 여러 메시지로 (보기용, 앱으로 가져오기는 안 됨)
  static List<String> historyText({
    required List<GiftRecord> records,
    DateTime? now,
    int chunkSize = kShareChunkSize,
  }) {
    final sorted = [...records]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : (b.id ?? 0).compareTo(a.id ?? 0);
      });
    String total(String direction) {
      final part = records.where((r) => r.direction == direction);
      return '$direction ${part.length}건 ${formatWon(part.fold(0, (s, r) => s + r.amount))}';
    }

    final lines = [
      for (var i = 0; i < sorted.length; i++)
        '${i + 1}. ${historyLine(sorted[i])}',
    ];
    final count = lines.isEmpty ? 1 : (lines.length + chunkSize - 1) ~/ chunkSize;
    final today = toDbDate(now ?? DateTime.now());
    return [
      for (var i = 0; i < count; i++)
        [
          '[경조사 장부] 주고받은 내역 · $today${count > 1 ? ' (${i + 1}/$count)' : ''}',
          '${total(Direction.sent)} / ${total(Direction.received)}',
          '',
          ...lines.skip(i * chunkSize).take(chunkSize),
          if (i < count - 1) '(${i + 1}/$count) 다음 메시지에 이어져요',
        ].join('\n'),
    ];
  }

  /// 날짜 · 보냄/받음 · 이름(관계) · 금액 · 결제 방법 · 행사 종류 · 행사 이름 · 메모 (빈 값은 뺀다)
  static String historyLine(GiftRecord r) {
    final name = r.personName ?? '';
    final relation = r.personRelation ?? '';
    final memo = (r.memo ?? '').trim();
    return [
      toDbDate(r.date),
      r.direction,
      relation.isEmpty ? name : '$name($relation)',
      formatWon(r.amount),
      r.method,
      r.eventType ?? '',
      r.eventTitle ?? '',
      if (memo.isNotEmpty) '메모: ${LedgerText.clean(memo)}',
    ].where((v) => v.trim().isNotEmpty).join(' · ');
  }

  // ───────────────────────── ② 주고받은 내역 ─────────────────────────

  static const historyHeader = [
    '날짜', '보냄/받음', '이름', '관계', '연락처', '금액', '결제 방법', '행사 종류',
    '행사 이름', '행사 날짜', '장소', '구분', '식권', '메모',
    '확인 필요', // 장부를 가져올 때 동명이인이 의심되어 표시한 기록
  ];
  static const peopleHeader = [
    '이름', '관계', '연락처', '사람 메모', '보낸 횟수', '보낸 합계', '받은 횟수', '받은 합계',
    '차이(받음 - 보냄)', '등록한 날',
  ];
  static const eventsHeader = [
    '행사 날짜', '종류', '행사 이름', '장소', '내 행사 여부', '메모',
    '연결된 사람', '알림', '얼마 내셨어요 숨김', '구분 목록',
  ];

  /// [records]: 모든 기록, [people]: 모든 사람, [events]: 모든 행사(일정 포함)
  static Uint8List buildHistory({
    required List<GiftRecord> records,
    required List<Person> people,
    required List<Event> events,
    DateTime? now,
  }) {
    final book = _Book();
    final peopleById = {for (final p in people) p.id: p};
    final eventsById = {for (final e in events) e.id: e};

    // [내역] 날짜 최신순
    final sorted = [...records]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : (b.id ?? 0).compareTo(a.id ?? 0);
      });
    final list = book.sheet('내역');
    list.header(0, historyHeader);
    for (var i = 0; i < sorted.length; i++) {
      final r = sorted[i];
      final p = peopleById[r.personId];
      final e = eventsById[r.eventId];
      final row = 1 + i;
      list
        ..text(row, 0, toDbDate(r.date))
        ..text(row, 1, r.direction)
        ..text(row, 2, r.personName ?? p?.name ?? '')
        ..text(row, 3, r.personRelation ?? p?.relation ?? '')
        ..text(row, 4, p?.phone ?? '')
        ..number(row, 5, r.amount)
        ..text(row, 6, r.method)
        ..text(row, 7, e?.type ?? r.eventType ?? '')
        ..text(row, 8, e?.title ?? r.eventTitle ?? '')
        ..text(row, 9, e == null ? '' : toDbDate(e.date))
        ..text(row, 10, e?.place ?? '')
        ..text(row, 11, r.side ?? '')
        ..intOrBlank(row, 12, r.mealTickets)
        ..text(row, 13, r.memo ?? '')
        ..text(row, 14, r.needsReview ? '확인 필요' : '');
    }
    // 맨 아래: 보냄 · 받음 건수와 합계
    var row = sorted.length + 2;
    for (final direction in [Direction.sent, Direction.received]) {
      final part = records.where((r) => r.direction == direction);
      list
        ..text(row, 0, '$direction 합계', bold: true)
        ..text(row, 1, '${part.length}건', bold: true)
        ..number(row, 5, part.fold(0, (s, r) => s + r.amount), bold: true);
      row++;
    }
    list.freezeRows = 1;

    // [사람별 합계] 이름순
    final sum = book.sheet('사람별 합계');
    sum.header(0, peopleHeader);
    final byName = [...people]..sort((a, b) {
        final c = a.name.compareTo(b.name);
        return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
      });
    for (var i = 0; i < byName.length; i++) {
      final p = byName[i];
      final mine = records.where((r) => r.personId == p.id);
      final sent = mine.where((r) => r.isSent);
      final received = mine.where((r) => !r.isSent);
      final sentTotal = sent.fold(0, (s, r) => s + r.amount);
      final receivedTotal = received.fold(0, (s, r) => s + r.amount);
      final row = 1 + i;
      sum
        ..text(row, 0, p.name)
        ..text(row, 1, p.relation)
        ..text(row, 2, p.phone ?? '')
        ..text(row, 3, p.memo ?? '')
        ..number(row, 4, sent.length, money: false)
        ..number(row, 5, sentTotal)
        ..number(row, 6, received.length, money: false)
        ..number(row, 7, receivedTotal)
        ..number(row, 8, receivedTotal - sentTotal)
        ..text(row, 9, toDbDate(p.createdAt));
    }
    sum.freezeRows = 1;

    // [행사 일정] 아직 돈을 안 적은 일정도 포함, 날짜 최신순
    final schedule = book.sheet('행사 일정');
    schedule.header(0, eventsHeader);
    final byDate = [...events]..sort((a, b) {
        final c = b.date.compareTo(a.date);
        return c != 0 ? c : (b.id ?? 0).compareTo(a.id ?? 0);
      });
    for (var i = 0; i < byDate.length; i++) {
      final e = byDate[i];
      final row = 1 + i;
      schedule
        ..text(row, 0, toDbDate(e.date))
        ..text(row, 1, e.type)
        ..text(row, 2, e.title)
        ..text(row, 3, e.place ?? '')
        ..text(row, 4, e.isMine ? '예' : '아니요')
        ..text(row, 5, e.memo ?? '')
        ..text(row, 6, peopleById[e.personId]?.name ?? '')
        ..text(row, 7, e.hasReminder ? reminderLabel(e) : '끔')
        ..text(row, 8, e.pendingHidden ? '숨김' : '')
        ..text(row, 9, [
          for (final s in e.sides)
            if (s != ReceptionDefaults.noSide) s,
        ].join(', '));
    }
    schedule.freezeRows = 1;

    book.info(kindHistory, now ?? DateTime.now());
    return book.encode();
  }
}

/// 행사 장부 한 줄
class LedgerExcelRow {
  const LedgerExcelRow({
    required this.name,
    required this.amount,
    this.side = '',
    this.method = '',
    this.mealTickets,
    this.memo = '',
    required this.date,
    this.time,
    this.relation = '',
    this.phone = '',
    this.needsReview = false,
    required this.order,
  });
  final String name;
  final int amount;
  final String side;
  final String method;
  final int? mealTickets;
  final String memo;
  final DateTime date;

  /// 받은 시각 (다른 사람 행사 · 접수로 받은 손님만)
  final DateTime? time;
  final String relation;
  final String phone;
  final bool needsReview;

  /// 받은 순서
  final int order;
}

/// 행사 장부 엑셀의 재료: 1~2행 행사 정보 + 손님 줄 (이미 고른 순서대로)
class LedgerExcel {
  const LedgerExcel({
    required this.title,
    required this.date,
    required this.info,
    required this.rows,
    this.sides = const [],
    this.type = '',
    this.isMine = false,
    this.place = '',
    this.memo = '',
  });
  final String title;
  final DateTime date;

  /// [행사 목록] 시트에 쓰는 값
  final String type;
  final bool isMine;
  final String place;
  final String memo;

  /// 행사에 정한 구분 (합계 시트에 0명이어도 넣는다)
  final List<String> sides;

  /// (제목, 값). 값이 빈 칸이면 엑셀에 넣지 않는다.
  final List<(String, String)> info;
  final List<LedgerExcelRow> rows;

  String get fileName => ExportService.ledgerFileName(title, date);

  static String _time(DateTime? d) =>
      d == null ? '' : DateFormat('yyyy-MM-dd HH:mm').format(d);

  static List<LedgerExcelRow> _ordered(List<LedgerExcelRow> rows, LedgerOrder order) {
    final list = [...rows];
    switch (order) {
      case LedgerOrder.name:
        list.sort((a, b) {
          final c = a.name.compareTo(b.name);
          return c != 0 ? c : a.order.compareTo(b.order);
        });
      case LedgerOrder.received:
        list.sort((a, b) => a.order.compareTo(b.order));
    }
    return list;
  }

  /// 다른 사람 행사 (또는 받기 중인 장부). 지운 항목은 뺀다.
  factory LedgerExcel.fromReception(ReceptionPackage package,
      {LedgerOrder order = LedgerOrder.name}) {
    final r = package.reception;
    final rows = [
      for (final e in package.entries)
        if (!e.deleted)
          LedgerExcelRow(
            name: e.name,
            amount: e.amount,
            side: e.side == ReceptionDefaults.noSide ? '' : e.side,
            method: r.methodEnabled || e.method == ReceptionDefaults.transfer
                ? e.method
                : '',
            mealTickets:
                r.mealTicketEnabled || e.mealTickets > 0 ? e.mealTickets : null,
            memo: e.memo ?? '',
            date: e.createdAt,
            time: e.createdAt,
            order: e.createdAt.microsecondsSinceEpoch,
          ),
    ];
    return LedgerExcel(
      title: r.title,
      date: r.date,
      info: [
        ('행사 이름', r.title),
        ('종류', r.eventType),
        ('날짜', toDbDate(r.date)),
        ('행사 구분', r.imported ? '다른 사람 행사 (내 행사로 옮김)' : '다른 사람 행사'),
        ('적은 사람', r.operatorName),
        ('구분 목록', [
          for (final s in r.sides)
            if (s != ReceptionDefaults.noSide) s,
        ].join(', ')),
        ('받기 시작', _time(r.startedAt)),
        ('받기 끝', _time(r.finishedAt)),
      ],
      rows: _ordered(rows, order),
      type: r.eventType,
      sides: [
        for (final s in r.sides)
          if (s != ReceptionDefaults.noSide) s,
      ],
    );
  }

  /// 내 행사: 받은 기록 + 사람 정보(관계 · 연락처)
  factory LedgerExcel.fromEvent(Event event, List<GiftRecord> records,
      Map<int?, Person> people,
      {LedgerOrder order = LedgerOrder.name}) {
    final rows = [
      for (final r in records)
        if (!r.isSent)
          LedgerExcelRow(
            name: r.personName ?? people[r.personId]?.name ?? '',
            amount: r.amount,
            side: r.side == null || r.side == ReceptionDefaults.noSide ? '' : r.side!,
            method: r.method,
            mealTickets: r.mealTickets,
            memo: r.memo ?? '',
            date: r.date,
            relation: r.personRelation ?? people[r.personId]?.relation ?? '',
            phone: people[r.personId]?.phone ?? '',
            needsReview: r.needsReview,
            order: r.id ?? 0,
          ),
    ];
    return LedgerExcel(
      title: event.title,
      date: event.date,
      info: [
        ('행사 이름', event.title),
        ('종류', event.type),
        ('날짜', toDbDate(event.date)),
        ('행사 구분', event.isMine ? '내 행사' : '다른 사람 행사'),
        ('장소', event.place ?? ''),
        ('메모', event.memo ?? ''),
        ('구분 목록', [
          for (final s in event.sides)
            if (s != ReceptionDefaults.noSide) s,
        ].join(', ')),
        ('알림', event.hasReminder ? reminderLabel(event) : ''),
      ],
      rows: _ordered(rows, order),
      type: event.type,
      isMine: event.isMine,
      place: event.place ?? '',
      memo: event.memo ?? '',
      sides: [
        for (final s in event.sides)
          if (s != ReceptionDefaults.noSide) s,
      ],
    );
  }
}

/// excel 패키지 위에 칸 쓰기 · 열 너비 · 첫 줄 고정 · 숨긴 시트를 얹는다.
class _Book {
  _Book() : excel = Excel.createExcel() {
    _defaultSheet = excel.getDefaultSheet();
  }
  final Excel excel;
  String? _defaultSheet;
  final _sheets = <_Sheet>[];

  _Sheet sheet(String name) {
    // 처음 만든 시트는 기본 시트(Sheet1)의 이름을 바꿔 쓴다
    if (_defaultSheet != null) {
      excel.rename(_defaultSheet!, name);
      _defaultSheet = null;
    }
    final s = _Sheet(name, excel[name]);
    _sheets.add(s);
    return s;
  }

  void info(String kind, DateTime now) {
    final s = sheet('정보');
    s
      ..text(0, 0, '앱 이름', bold: true)
      ..text(0, 1, ExportService.appName)
      ..text(1, 0, '파일 종류', bold: true)
      ..text(1, 1, kind)
      ..text(2, 0, '형식 버전', bold: true)
      ..number(2, 1, ExportService.formatVersion, money: false)
      ..text(3, 0, '만든 날짜', bold: true)
      ..text(3, 1, DateFormat('yyyy-MM-dd HH:mm').format(now));
    s.hidden = true;
  }

  Uint8List encode() {
    for (final s in _sheets) {
      s.applyWidths();
    }
    excel.setDefaultSheet(_sheets.first.name);
    final bytes = excel.save()!;
    return _patch(Uint8List.fromList(bytes));
  }

  /// excel 패키지가 못 하는 첫 줄 고정과 시트 숨기기를 파일 안의 XML에 직접 넣는다.
  Uint8List _patch(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    String read(String name) =>
        utf8.decode(archive.findFile(name)!.content as List<int>);

    final workbook = read('xl/workbook.xml');
    final rels = read('xl/_rels/workbook.xml.rels');
    final changed = <String, String>{};
    var newWorkbook = workbook;

    for (final s in _sheets) {
      final sheetTag = RegExp('<sheet [^>]*name="${RegExp.escape(_xml(s.name))}"[^>]*/>')
          .firstMatch(newWorkbook);
      if (sheetTag == null) continue;
      final tag = sheetTag.group(0)!;
      if (s.hidden) {
        final hiddenTag = tag.contains('state=')
            ? tag.replaceFirst(RegExp(r'state="[^"]*"'), 'state="hidden"')
            : tag.replaceFirst('<sheet ', '<sheet state="hidden" ');
        newWorkbook = newWorkbook.replaceFirst(tag, hiddenTag);
      }
      if (s.freezeRows > 0) {
        final rid = RegExp(r'r:id="([^"]+)"').firstMatch(tag)?.group(1);
        final target = rid == null
            ? null
            : RegExp('Id="${RegExp.escape(rid)}"[^>]*Target="([^"]+)"')
                    .firstMatch(rels)
                    ?.group(1) ??
                RegExp('Target="([^"]+)"[^>]*Id="${RegExp.escape(rid)}"')
                    .firstMatch(rels)
                    ?.group(1);
        if (target == null) continue;
        final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
        final xml = changed[path] ?? read(path);
        changed[path] = _freeze(xml, s.freezeRows);
      }
    }
    changed['xl/workbook.xml'] = newWorkbook;

    final out = Archive();
    for (final f in archive.files) {
      final replaced = changed[f.name];
      if (replaced != null) {
        final data = utf8.encode(replaced);
        out.addFile(ArchiveFile(f.name, data.length, data));
      } else {
        out.addFile(f);
      }
    }
    return Uint8List.fromList(ZipEncoder().encode(out)!);
  }

  /// 시트 XML에 첫 줄([rows]줄) 고정을 넣는다.
  static String _freeze(String xml, int rows) {
    final cell = 'A${rows + 1}';
    final pane =
        '<pane ySplit="$rows" topLeftCell="$cell" activePane="bottomLeft" state="frozen"/>'
        '<selection pane="bottomLeft" activeCell="$cell" sqref="$cell"/>';
    final view = RegExp(r'<sheetView\b[^>]*?(/>|>)').firstMatch(xml);
    if (view != null) {
      final tag = view.group(0)!;
      if (tag.endsWith('/>')) {
        return xml.replaceFirst(tag, '${tag.substring(0, tag.length - 2)}>$pane</sheetView>');
      }
      return xml.replaceFirst(tag, '$tag$pane');
    }
    // sheetViews가 없으면 sheetData · cols · sheetFormatPr 앞에 넣는다
    final views = '<sheetViews><sheetView workbookViewId="0">$pane</sheetView></sheetViews>';
    for (final anchor in ['<sheetFormatPr', '<cols', '<sheetData']) {
      final i = xml.indexOf(anchor);
      if (i >= 0) return xml.replaceRange(i, i, views);
    }
    return xml;
  }

  static String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

class _Sheet {
  _Sheet(this.name, this.sheet);
  final String name;
  final Sheet sheet;
  bool hidden = false;
  int freezeRows = 0;

  /// 열마다 가장 긴 글자 폭 (한글은 영문 두 글자 폭으로 센다)
  final _widths = <int, int>{};

  static final _bold = CellStyle(bold: true);
  static final _money = CellStyle(numberFormat: NumFormat.standard_3);
  static final _boldMoney =
      CellStyle(bold: true, numberFormat: NumFormat.standard_3);

  void _measure(int col, String text) {
    var w = 0;
    for (final rune in text.runes) {
      w += rune < 0x1100 ? 1 : 2;
    }
    if (w > (_widths[col] ?? 0)) _widths[col] = w;
  }

  CellIndex _at(int row, int col) =>
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);

  /// 빈 값도 빈 문자열 칸으로 남겨 열 위치를 늘 같게 한다.
  void text(int row, int col, String value, {bool bold = false}) {
    sheet.updateCell(_at(row, col), TextCellValue(value),
        cellStyle: bold ? _bold : null);
    _measure(col, value);
  }

  void number(int row, int col, int value, {bool money = true, bool bold = false}) {
    sheet.updateCell(_at(row, col), IntCellValue(value),
        cellStyle: money
            ? (bold ? _boldMoney : _money)
            : (bold ? _bold : null));
    _measure(col, money ? formatNumber(value) : '$value');
  }

  void intOrBlank(int row, int col, int? value) =>
      value == null ? text(row, col, '') : number(row, col, value, money: false);

  void header(int row, List<String> titles) {
    for (var i = 0; i < titles.length; i++) {
      text(row, i, titles[i], bold: true);
    }
  }

  void applyWidths() {
    for (final MapEntry(key: col, value: w) in _widths.entries) {
      sheet.setColumnWidth(col, (w + 3).clamp(6, 60).toDouble());
    }
  }
}
