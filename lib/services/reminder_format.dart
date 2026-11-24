import '../models/event.dart';

/// 일정 알림 문구 (추가 AC)

/// 고를 수 있는 '며칠 전' (칩 순서): 없음 · 2일 전 · 1일 전 · 당일
const reminderDayOptions = <int?>[null, 2, 1, 0];

/// [없음] [2일 전] [1일 전] [당일]
String reminderDaysLabel(int? days) => switch (days) {
      null => '없음',
      0 => '당일',
      _ => '$days일 전',
    };

/// 시각(0~23) → '오전 7시' · '낮 12시' · '오후 6시' · '밤 12시'
String hourLabel(int hour) => switch (hour) {
      0 => '밤 12시',
      12 => '낮 12시',
      < 12 => '오전 $hour시',
      _ => '오후 ${hour - 12}시',
    };

/// '1일 전 오전 9시'. 알림이 없으면 '없음'
String reminderLabel(Event e) => e.reminderDays == null
    ? '없음'
    : '${reminderDaysLabel(e.reminderDays)} ${hourLabel(e.reminderHour)}';

/// 알림 제목 앞말: 당일 '오늘', 1일 전 '내일', 2일 전 '모레'
String reminderWhenWord(int days) => switch (days) {
      0 => '오늘',
      1 => '내일',
      2 => '모레',
      _ => '$days일 뒤',
    };
