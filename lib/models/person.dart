class Person {
  final int? id;
  final String name;
  final String relation;
  final String? phone;
  final String? memo;
  final DateTime createdAt;

  const Person({
    this.id,
    required this.name,
    this.relation = '기타',
    this.phone,
    this.memo,
    required this.createdAt,
  });

  factory Person.fromMap(Map<String, Object?> m) => Person(
        id: m['id'] as int?,
        name: m['name'] as String,
        relation: (m['relation'] as String?) ?? '기타',
        phone: m['phone'] as String?,
        memo: m['memo'] as String?,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'relation': relation,
        'phone': phone,
        'memo': memo,
        'created_at': createdAt.toIso8601String(),
      };

  Person copyWith({
    String? name,
    String? relation,
    String? phone,
    String? memo,
  }) =>
      Person(
        id: id,
        name: name ?? this.name,
        relation: relation ?? this.relation,
        phone: phone ?? this.phone,
        memo: memo ?? this.memo,
        createdAt: createdAt,
      );
}

/// 사람 목록에 보여줄 요약 (보냄/받음 합계 포함).
class PersonSummary {
  final Person person;
  final int sentTotal;
  final int receivedTotal;

  const PersonSummary({
    required this.person,
    required this.sentTotal,
    required this.receivedTotal,
  });
}
