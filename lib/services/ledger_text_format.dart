import '../models/constants.dart';
import '../models/event.dart';
import '../models/reception.dart';
import 'app_config.dart';
import 'format.dart';

/// 장부 보내기 한 메시지에 넣는 최대 인원. 넘으면 이 단위로 나눠 보낸다.
const kShareChunkSize = 100;

/// 명단 순서
enum LedgerOrder {
  /// 가나다순 (기본)
  name,

  /// 받은 순서
  received,
}

/// 장부 보내기 글의 형식. 보내기([LedgerText.build])와 붙여넣어 가져오기([LedgerText.parse])가
/// 같은 형식을 쓰도록 이 파일 하나에 모았다. 형식을 바꾸면 둘을 함께 고치고 왕복 테스트를 돌린다.
///
/// ```text
/// [경조사 장부] 누나 결혼식 받은 명단 (1/4)
/// 2026년 12월 26일 (토) · 받은 사람: 송희강
///
/// 총 312명 · 25,350,000원
/// - 신랑측 160명 · 13,200,000원
/// - 신부측 152명 · 12,150,000원
/// 현금 22,000,000원 · 계좌 3,350,000원 · 식권 330장
///
/// 1. 강민호 · 100,000원 · 신랑측 · 현금 · 오전 11:52
/// 2. 강지은 · 50,000원 · 신부측 · 계좌 · 식권 2 · 오후 12:03 · 메모: 봉투 2개
/// (1/4) 다음 메시지에 이어져요
///
/// 경조사 장부 앱으로 정리했어요
/// 앱 받기: (Play 스토어 링크)
/// ```
class LedgerText {
  static const _sep = ' · ';
  static const _appName = '[경조사 장부]';
  /// 끝 줄 (그 아래 Play 스토어 링크). 가져오기 안내는 v1에서 뺐다(추가 X).
  static const guideLine = '경조사 장부 앱으로 정리했어요';
  static const _storeLabel = '앱 받기: ';
  static const _noSideLabel = '구분 없음';

  /// 이름 · 메모에 구분 기호(·)나 줄바꿈이 있으면 읽을 때 칸이 어긋나므로 바꿔 둔다.
  static String clean(String s) => s
      .replaceAll(RegExp(r'[·•ㆍ]'), '-')
      .replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ')
      .trim();

  /// 보낼 메시지들. 인원이 [chunkSize]를 넘으면 여러 개로 나누고, 메시지마다
  /// 머리말과 합계를 다시 넣는다. 값이 없는 항목은 넣지 않는다.
  static List<String> build(
    ReceptionPackage package, {
    LedgerOrder order = LedgerOrder.name,
    bool includeMemo = true,
    int chunkSize = kShareChunkSize,
    String storeUrl = AppConfig.playStoreUrl,
  }) {
    final entries = sorted(package.entries, order);
    final chunkCount =
        entries.isEmpty ? 1 : (entries.length + chunkSize - 1) ~/ chunkSize;
    final summary = _summary(package);
    return [
      for (var i = 0; i < chunkCount; i++)
        [
          ..._header(package.reception, i, chunkCount),
          '',
          ...summary,
          '',
          for (var n = i * chunkSize;
              n < entries.length && n < (i + 1) * chunkSize;
              n++)
            '${n + 1}. ${entryLine(entries[n], package, includeMemo: includeMemo)}',
          if (i < chunkCount - 1) '(${i + 1}/$chunkCount) 다음 메시지에 이어져요',
          '',
          guideLine,
          '$_storeLabel$storeUrl',
        ].join('\n'),
    ];
  }

  /// 명단 순서대로 정렬한 사본
  static List<ReceptionEntry> sorted(
      List<ReceptionEntry> entries, LedgerOrder order) {
    final list = entries.where((e) => !e.deleted).toList();
    switch (order) {
      case LedgerOrder.name:
        list.sort((a, b) {
          final byName = a.name.compareTo(b.name);
          return byName != 0 ? byName : a.createdAt.compareTo(b.createdAt);
        });
      case LedgerOrder.received:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    return list;
  }

  static List<String> _header(Reception r, int index, int count) => [
        '$_appName ${clean(r.title)} 받은 명단'
            '${count > 1 ? ' (${index + 1}/$count)' : ''}',
        [
          formatDate(r.date),
          if (r.operatorName.trim().isNotEmpty)
            '받은 사람: ${clean(r.operatorName)}',
        ].join(_sep),
      ];

  static bool _showsMethod(ReceptionPackage p) =>
      p.reception.methodEnabled ||
      p.entries.any((e) => e.method == ReceptionDefaults.transfer);

  static List<String> _summary(ReceptionPackage p) {
    final totals = p.totals;
    final named = [
      for (final s in p.sides)
        if (s != ReceptionDefaults.noSide && p.totalsFor(s).count > 0) s,
    ];
    final noSide = p.totalsFor(ReceptionDefaults.noSide);
    final money = [
      if (_showsMethod(p)) ...[
        '현금 ${formatWon(p.totalsForMethod(ReceptionDefaults.cash).amount)}',
        '계좌 ${formatWon(p.totalsForMethod(ReceptionDefaults.transfer).amount)}',
      ],
      if (totals.mealTickets > 0) '식권 ${totals.mealTickets}장',
    ];
    return [
      '총 ${totals.count}명 · ${formatWon(totals.amount)}',
      for (final s in named)
        '- ${clean(s)} ${p.totalsFor(s).count}명 · ${formatWon(p.totalsFor(s).amount)}',
      if (named.isNotEmpty && noSide.count > 0)
        '- $_noSideLabel ${noSide.count}명 · ${formatWon(noSide.amount)}',
      if (money.isNotEmpty) money.join(_sep),
    ];
  }

  /// 받은 시각이 있는지. 내 행사 기록은 날짜만 있어(자정) 시각을 넣지 않는다.
  static bool hasTime(DateTime t) =>
      t.hour != 0 || t.minute != 0 || t.second != 0 || t.millisecond != 0;

  /// 명단 한 줄 (번호 제외): 이름 · 금액 · 구분 · 방법 · 식권 n · 받은 시각 · 메모: ...
  static String entryLine(ReceptionEntry e, ReceptionPackage p,
      {bool includeMemo = true}) {
    final memo = clean(e.memo ?? '');
    return [
      clean(e.name),
      formatWon(e.amount),
      if (e.side.isNotEmpty && e.side != ReceptionDefaults.noSide) clean(e.side),
      if (_showsMethod(p)) e.method == ReceptionDefaults.transfer ? '계좌' : '현금',
      if (e.mealTickets > 0) '식권 ${e.mealTickets}',
      if (hasTime(e.createdAt)) formatTime(e.createdAt),
      if (includeMemo && memo.isNotEmpty) '메모: $memo',
    ].join(_sep);
  }

  // ───────────────────────── 읽기 ─────────────────────────

  static final _headerRe =
      RegExp(r'^\[경조사 장부\]\s*(.+?)\s*받은 명단(?:\s*\((\d+)/(\d+)\))?$');
  static final _dateRe = RegExp(r'(\d{4})\s*년\s*(\d{1,2})\s*월\s*(\d{1,2})\s*일');
  static final _operatorRe = RegExp(r'받은 사람:\s*(.+)$');
  static final _entryRe = RegExp(r'^(\d+)\s*[.)]\s*(.+)$');
  static final _amountRe = RegExp(r'^([\d,]+)\s*원$');
  static final _mealRe = RegExp(r'^식권\s*(\d+)\s*(?:장|매)?$');
  static final _memoRe = RegExp(r'^메모\s*:\s*(.*)$');
  static final _timeRe = RegExp(r'^(오전|오후)\s*(\d{1,2}):(\d{2})$');
  static final _sideTotalRe = RegExp(r'^-\s*(.+?)\s+\d+명\s*·\s*[\d,]+원$');
  static final _skipRes = [
    RegExp(r'^총\s*\d+명'),
    RegExp(r'^(현금|계좌|식권)\s*[\d,]+\s*(원|장)'),
    RegExp(r'^\(\d+/\d+\)\s*다음 메시지'),
    RegExp(r'^앱으로 정리하려면'),
    RegExp(r'^경조사 장부 앱으로 정리했어요'),
    RegExp(r'^앱 받기'),
    RegExp(r'^https?://'),
    RegExp(r'^(\.{3}|…)$'),
  ];

  /// 붙여 넣은 글을 읽는다. 이 앱이 만든 형식이 아니면 null.
  /// 읽지 못한 줄은 건너뛰고 [ParsedLedger.unreadable]에 센다.
  static ParsedLedger? parse(String text) {
    String? title;
    DateTime? date;
    var operatorName = '';
    final sides = <String>[];
    var methodShown = false;
    var mealShown = false;
    var unreadable = 0;
    final rows = <_Row>[];

    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final header = _headerRe.firstMatch(line);
      if (header != null) {
        title ??= header.group(1)!.trim();
        continue;
      }
      final entry = _entryRe.firstMatch(line);
      if (entry != null) {
        final row = _parseRow(entry.group(2)!);
        if (row == null) {
          unreadable++;
        } else {
          rows.add(row);
          if (row.method != null) methodShown = true;
          if (row.meals > 0) mealShown = true;
        }
        continue;
      }
      final d = _dateRe.firstMatch(line);
      if (d != null && line.indexOf(d.group(0)!) == 0) {
        date ??= DateTime(int.parse(d.group(1)!), int.parse(d.group(2)!),
            int.parse(d.group(3)!));
        final op = _operatorRe.firstMatch(line);
        if (op != null && operatorName.isEmpty) operatorName = op.group(1)!.trim();
        continue;
      }
      final sideTotal = _sideTotalRe.firstMatch(line);
      if (sideTotal != null) {
        final side = sideTotal.group(1)!.trim();
        if (side != _noSideLabel && !sides.contains(side)) sides.add(side);
        continue;
      }
      if (_skipRes.any((re) => re.hasMatch(line))) {
        if (line.startsWith('현금') || line.startsWith('계좌')) methodShown = true;
        if (line.contains('식권')) mealShown = true;
        continue;
      }
      unreadable++;
    }
    if (title == null && rows.isEmpty) return null;
    return ParsedLedger._(
      title: title ?? '',
      date: date,
      operatorName: operatorName,
      sides: sides,
      methodEnabled: methodShown,
      mealTicketEnabled: mealShown,
      rows: rows,
      unreadable: unreadable,
    );
  }

  static _Row? _parseRow(String body) {
    final parts = body.split('·').map((s) => s.trim()).toList();
    if (parts.length < 2 || parts[0].isEmpty) return null;
    final amount = _amountRe.firstMatch(parts[1]);
    final value =
        amount == null ? null : int.tryParse(amount.group(1)!.replaceAll(',', ''));
    if (value == null || value <= 0) return null;
    String? side;
    String? method;
    var meals = 0;
    String? memo;
    Duration? time;
    for (final token in parts.skip(2)) {
      if (token.isEmpty) continue;
      if (token == '현금') {
        method = ReceptionDefaults.cash;
      } else if (token == '계좌' || token == '계좌이체') {
        method = ReceptionDefaults.transfer;
      } else if (_mealRe.firstMatch(token) case final m?) {
        meals = int.parse(m.group(1)!);
      } else if (_timeRe.firstMatch(token) case final m?) {
        // 오전 12:05 → 0시 5분, 오후 12:05 → 12시 5분, 오후 1:05 → 13시 5분
        final h = int.parse(m.group(2)!) % 12 + (m.group(1) == '오후' ? 12 : 0);
        time = Duration(hours: h, minutes: int.parse(m.group(3)!));
      } else if (_memoRe.firstMatch(token) case final m?) {
        memo = m.group(1)!.trim();
      } else if (side == null && method == null && meals == 0 && memo == null) {
        side = token;
      } else {
        return null;
      }
    }
    return _Row(parts[0], value, side, method, meals, memo, time);
  }

  /// 행사 이름으로 종류를 짐작한다 (글에는 종류가 없다).
  static String guessType(String title) {
    if (title.contains('결혼')) return '결혼';
    if (title.contains('장례') || title.contains('부고') || title.contains('발인')) {
      return '장례';
    }
    if (title.contains('돌잔치') || title.contains('돌 ')) return '돌';
    if (title.contains('생일') || title.contains('칠순') || title.contains('환갑')) {
      return '생일';
    }
    if (title.contains('개업')) return '개업';
    return '기타';
  }
}

class _Row {
  const _Row(
      this.name, this.amount, this.side, this.method, this.meals, this.memo,
      this.time);
  final String name;
  final int amount;
  final String? side;
  final String? method;
  final int meals;
  final String? memo;

  /// 받은 시각 (그날 0시부터). 글에 시각이 없으면 null.
  final Duration? time;
}

/// 붙여 넣은 글에서 읽은 장부
class ParsedLedger {
  const ParsedLedger._({
    required this.title,
    required this.date,
    required this.operatorName,
    required this.sides,
    required this.methodEnabled,
    required this.mealTicketEnabled,
    required List<_Row> rows,
    required this.unreadable,
  }) : _rows = rows; // ignore: prefer_initializing_formals

  final String title;

  /// 머리말에 날짜가 없으면 null (가져올 때 오늘로)
  final DateTime? date;
  final String operatorName;
  final List<String> sides;
  final bool methodEnabled;
  final bool mealTicketEnabled;
  final List<_Row> _rows;

  /// 읽지 못하고 건너뛴 줄 수
  final int unreadable;

  int get count => _rows.length;
  int get total => _rows.fold(0, (s, r) => s + r.amount);

  /// 가져오기에 쓰는 장부 묶음.
  ///
  /// 항목 ID는 '행사 이름 + 날짜 + 이름 + 금액 + 구분'(같은 글 안에서 겹치면 순번)으로 만든다.
  /// 그래서 같은 메시지를 두 번 붙여도 이미 가져온 항목으로 보고 다시 저장하지 않는다.
  ReceptionPackage toPackage({DateTime? today}) {
    final day = date ?? dateOnly(today ?? DateTime.now());
    final key = 'text:$title|${toDbDate(day)}';
    final seen = <String, int>{};
    final entries = <ReceptionEntry>[];
    final allSides = [...sides];
    for (final (i, r) in _rows.indexed) {
      final side = r.side ?? ReceptionDefaults.noSide;
      if (side != ReceptionDefaults.noSide && !allSides.contains(side)) {
        allSides.add(side);
      }
      final base = '$key|${r.name}|${r.amount}|$side';
      final n = seen[base] = (seen[base] ?? 0) + 1;
      entries.add(ReceptionEntry(
        id: '$base#$n',
        receptionId: key,
        name: r.name,
        amount: r.amount,
        side: side,
        method: r.method ?? ReceptionDefaults.cash,
        mealTickets: r.meals,
        memo: r.memo == null || r.memo!.isEmpty ? null : r.memo,
        // 받은 시각이 있으면 그 시각, 없으면 글의 순서를 지키도록 1밀리초씩 늘린다
        createdAt: r.time == null
            ? day.add(Duration(milliseconds: i))
            : day.add(r.time!),
      ));
    }
    return ReceptionPackage(
      Reception(
        id: key,
        title: title.isEmpty ? '받은 장부' : title,
        eventType: LedgerText.guessType(title),
        date: day,
        sides: allSides.isEmpty ? const [ReceptionDefaults.noSide] : allSides,
        operatorName: operatorName,
        startedAt: day,
        finishedAt: day,
        mealTicketEnabled: mealTicketEnabled,
        defaultMealTickets: 1,
        methodEnabled: methodEnabled,
      ),
      entries,
    );
  }

  /// 새 내 행사로 만들 때의 행사
  Event newEvent({DateTime? today}) {
    final p = toPackage(today: today);
    final r = p.reception;
    return Event(
      type: r.eventType,
      title: r.title,
      date: r.date,
      isMine: true,
      notify: false,
      receiveSides: r.sides,
      mealTicketEnabled: r.mealTicketEnabled,
      defaultMealTickets: r.defaultMealTickets,
      methodEnabled: r.methodEnabled,
    );
  }
}
