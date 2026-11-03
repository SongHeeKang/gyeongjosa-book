import '../models/gift_record.dart';
import '../models/person.dart';
import 'repository.dart';

/// 개발 모드에서만 쓰는 테스트용 샘플 데이터 (사람 5명, 내역 10개).
Future<void> insertSampleData(Repository repo) async {
  final now = DateTime.now();
  final people = [
    ('김철수', '친구', '010-1234-5678'),
    ('이영희', '회사', '010-2345-6789'),
    ('박민수', '가족', null),
    ('최지은', '지인', null),
    ('정우성', '친구', '010-9876-5432'),
  ];
  final ids = <int>[];
  for (final (name, relation, phone) in people) {
    ids.add(await repo.insertPerson(Person(
      name: '$name(샘플)',
      relation: relation,
      phone: phone,
      createdAt: now,
    )));
  }

  final records = [
    (0, '보냄', 100000, '결혼', 400),
    (0, '받음', 100000, '결혼', 30),
    (1, '보냄', 50000, '결혼', 200),
    (1, '보냄', 50000, '장례', 90),
    (2, '받음', 200000, '결혼', 30),
    (2, '보냄', 300000, '돌', 120),
    (3, '받음', 50000, '결혼', 30),
    (3, '보냄', 50000, '개업', 60),
    (4, '보냄', 100000, '장례', 10),
    (4, '받음', 50000, '생일', 5),
  ];
  for (final (idx, direction, amount, type, daysAgo) in records) {
    await repo.insertRecord(GiftRecord(
      personId: ids[idx],
      direction: direction,
      amount: amount,
      method: amount >= 100000 ? '계좌' : '현금',
      date: now.subtract(Duration(days: daysAgo)),
      eventType: type,
    ));
  }
}
