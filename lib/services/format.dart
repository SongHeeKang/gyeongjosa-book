import 'package:intl/intl.dart';

final _won = NumberFormat('#,###', 'ko_KR');
final _dbDate = DateFormat('yyyy-MM-dd');

/// 50000 → "50,000원"
String formatWon(int amount) => '${_won.format(amount)}원';

/// 50000 → "50,000"
String formatNumber(int amount) => _won.format(amount);

/// 금액을 "5만", "10만" 처럼 짧게
String formatManWon(int amount) {
  if (amount % 10000 == 0) return '${amount ~/ 10000}만';
  return formatNumber(amount);
}

/// 입력한 금액을 읽기 쉽게: 70,000 → 7만원, 35,000 → 3만 5천원, 12,345 → 1만 2,345원
String formatReadableWon(int amount) {
  final eok = amount ~/ 100000000;
  final man = amount % 100000000 ~/ 10000;
  final rest = amount % 10000;
  return '${[
    if (eok > 0) '$eok억',
    if (man > 0) '${formatNumber(man)}만',
    if (rest > 0) rest % 1000 == 0 ? '${rest ~/ 1000}천' : formatNumber(rest),
    if (amount == 0) '0',
  ].join(' ')}원';
}

/// 2026년 11월 3일 (화)
String formatDate(DateTime d) => DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(d);

/// 11월 3일
String formatShortDate(DateTime d) => DateFormat('M월 d일', 'ko_KR').format(d);

/// 오후 12:34
String formatTime(DateTime d) => DateFormat('a h:mm', 'ko_KR').format(d);

/// 2026.11.03
String formatDotDate(DateTime d) => DateFormat('yyyy.MM.dd').format(d);

String toDbDate(DateTime d) => _dbDate.format(d);

DateTime parseDbDate(String? s) {
  if (s == null) return DateTime.now();
  return DateTime.tryParse(s) ?? DateTime.now();
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// D-day 문구: 오늘 → "오늘", 내일 → "내일", 그 외 "D-3"
String dDay(DateTime date) {
  final diff = dateOnly(date).difference(dateOnly(DateTime.now())).inDays;
  if (diff == 0) return '오늘';
  if (diff == 1) return '내일';
  if (diff > 0) return 'D-$diff';
  return '${-diff}일 전';
}
