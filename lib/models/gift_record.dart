import '../services/format.dart';

/// 주고받은 내역 1건. (Dart 기본 타입 Record와 이름이 겹치지 않게 GiftRecord)
class GiftRecord {
  final int? id;
  final int personId;
  final int? eventId;

  /// '보냄' 또는 '받음'
  final String direction;
  final int amount;
  final String method;
  final DateTime date;
  final String? memo;

  /// 행사와 연결되지 않은 내역의 행사 종류 (결혼/장례/...)
  final String? eventType;

  /// 받은 장부를 가져올 때 동명이인이 의심되어 확인이 필요한 내역
  final bool needsReview;

  /// 행사장 접수에서 온 기록의 구분(신랑측 등) · 식권 매수. 없으면 null.
  final String? side;
  final int? mealTickets;

  // 조회 시 함께 가져오는 표시용 값
  final String? personName;
  final String? personRelation;
  final String? eventTitle;

  const GiftRecord({
    this.id,
    required this.personId,
    this.eventId,
    required this.direction,
    required this.amount,
    this.method = '현금',
    required this.date,
    this.memo,
    this.eventType,
    this.needsReview = false,
    this.side,
    this.mealTickets,
    this.personName,
    this.personRelation,
    this.eventTitle,
  });

  bool get isSent => direction == '보냄';

  factory GiftRecord.fromMap(Map<String, Object?> m) => GiftRecord(
        id: m['id'] as int?,
        personId: m['person_id'] as int,
        eventId: m['event_id'] as int?,
        direction: (m['direction'] as String?) ?? '보냄',
        amount: m['amount'] as int? ?? 0,
        method: (m['method'] as String?) ?? '현금',
        date: parseDbDate(m['date'] as String?),
        memo: m['memo'] as String?,
        eventType: (m['ev_type'] as String?) ?? (m['event_type'] as String?),
        needsReview: (m['needs_review'] as int? ?? 0) == 1,
        side: m['side'] as String?,
        mealTickets: m['meal_tickets'] as int?,
        personName: m['person_name'] as String?,
        personRelation: m['person_relation'] as String?,
        eventTitle: m['event_title'] as String?,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'person_id': personId,
        'event_id': eventId,
        'direction': direction,
        'amount': amount,
        'method': method,
        'date': toDbDate(date),
        'memo': memo,
        'event_type': eventType,
        'needs_review': needsReview ? 1 : 0,
        'side': side,
        'meal_tickets': mealTickets,
      };

  /// 화면에 보여줄 행사 이름 (예: "결혼 · 철수 결혼식")
  String get eventLabel {
    final parts = <String>[
      if (eventType != null && eventType!.isNotEmpty) eventType!,
      if (eventTitle != null && eventTitle!.isNotEmpty) eventTitle!,
    ];
    return parts.join(' · ');
  }
}
