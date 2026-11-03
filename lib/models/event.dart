import '../services/format.dart';

class Event {
  final int? id;
  final String type;
  final String title;
  final DateTime date;
  final bool isMine;
  final String? place;
  final String? memo;

  /// 전날 오전 9시 알림 여부
  final bool notify;

  const Event({
    this.id,
    required this.type,
    required this.title,
    required this.date,
    required this.isMine,
    this.place,
    this.memo,
    this.notify = true,
  });

  factory Event.fromMap(Map<String, Object?> m) => Event(
        id: m['id'] as int?,
        type: (m['type'] as String?) ?? '기타',
        title: (m['title'] as String?) ?? '',
        date: parseDbDate(m['date'] as String?),
        isMine: (m['is_mine'] as int? ?? 0) == 1,
        place: m['place'] as String?,
        memo: m['memo'] as String?,
        notify: (m['notify'] as int? ?? 1) == 1,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'type': type,
        'title': title,
        'date': toDbDate(date),
        'is_mine': isMine ? 1 : 0,
        'place': place,
        'memo': memo,
        'notify': notify ? 1 : 0,
      };
}

/// 장부 목록/상세에 쓰는 행사 요약.
class EventSummary {
  final Event event;
  final int count;
  final int total;

  const EventSummary({
    required this.event,
    required this.count,
    required this.total,
  });
}
