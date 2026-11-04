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
