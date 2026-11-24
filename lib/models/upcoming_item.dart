import 'event.dart';
import 'reception.dart';

/// 홈 '일정'에 보이는 날짜가 있는 항목의 종류 (추가 AC)
enum UpcomingKind {
  /// 일정 추가로 등록한 남의 행사(청첩장 · 부고)
  schedule('일정'),

  /// 내 행사
  myEvent('내 행사'),

  /// 다른 사람 행사(대신 받아 주는 행사)
  otherEvent('다른 사람 행사');

  const UpcomingKind(this.label);

  /// 목록의 라벨 칩 글자
  final String label;
}

/// 다가오는 일정 · 날짜별 내역의 일정 · 행사 한 줄.
/// 보냈어요 · 받음 기록은 일정이 아니라 여기에 넣지 않는다.
class UpcomingItem {
  const UpcomingItem({
    required this.kind,
    required this.title,
    required this.date,
    this.event,
    this.reception,
  });

  factory UpcomingItem.fromEvent(Event e) => UpcomingItem(
        kind: e.isMine ? UpcomingKind.myEvent : UpcomingKind.schedule,
        title: e.title,
        date: e.date,
        event: e,
      );

  factory UpcomingItem.fromReception(Reception r) => UpcomingItem(
        kind: UpcomingKind.otherEvent,
        title: r.title,
        date: r.date,
        reception: r,
      );

  final UpcomingKind kind;
  final String title;
  final DateTime date;

  /// 일정 · 내 행사면 그 행사
  final Event? event;

  /// 다른 사람 행사면 그 장부
  final Reception? reception;

  /// 알림을 켜 둔 일정 · 행사인지 (목록 이름 옆 작은 종)
  bool get hasReminder => event?.hasReminder ?? false;

  /// 같은 날이면 일정 → 내 행사 → 다른 사람 행사 순
  static int compare(UpcomingItem a, UpcomingItem b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.kind.index.compareTo(b.kind.index);
  }
}
