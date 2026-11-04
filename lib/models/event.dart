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

  /// 남의 행사(일정)에 연결된 사람. 이전 버전에서 만든 일정은 없을 수 있다.
  final int? personId;

  /// '얼마 내셨어요?'에서 '안 갔어요'를 눌러 숨겼는지
  final bool pendingHidden;

  /// 연결된 사람의 관계 (읽을 때만 채워짐)
  final String? personRelation;

  const Event({
    this.id,
    required this.type,
    required this.title,
    required this.date,
    required this.isMine,
    this.place,
    this.memo,
    this.notify = true,
    this.personId,
    this.pendingHidden = false,
    this.personRelation,
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
        personId: m['person_id'] as int?,
        pendingHidden: (m['pending_hidden'] as int? ?? 0) == 1,
        personRelation: m['person_relation'] as String?,
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
        'person_id': personId,
        'pending_hidden': pendingHidden ? 1 : 0,
      };

  /// 일정 이름: 김철수 + 결혼 → '김철수 결혼식'
  static String scheduleTitle(String name, String type) {
    const words = {
      '결혼': '결혼식',
      '장례': '장례식',
      '돌': '돌잔치',
      '생일': '생일',
      '개업': '개업식',
    };
    final word = words[type];
    return word == null ? name : '$name $word';
  }
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
