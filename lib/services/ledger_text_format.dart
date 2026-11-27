import '../models/constants.dart';
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

/// 장부 보내기 글의 형식 (행사 상세 · 받기 끝내기의 텍스트 공유).
/// 받은 장부를 붙여 넣어 가져오는 읽기 기능은 v1에서 없앴다(2026-11-27, 코드 삭제).
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

  /// 이름 · 메모에 구분 기호(·)나 줄바꿈이 있으면 줄이 어긋나 보이므로 바꿔 둔다.
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
}

