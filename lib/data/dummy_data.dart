import '../models/constants.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../models/person.dart';
import 'repository.dart';

/// 테스트 전용 더미 데이터: 사람 50명, 행사 50개, 보내고 받은 기록 50건.
/// 메모에 [dummyDataMarker]를 남겨, 끌 때 직접 입력한 기록은 건드리지 않고 이것만 지운다.
/// Google Play 업로드 전에 설정의 테스트 메뉴와 함께 사라진다 (AppConfig.testBuild).
Future<void> insertDummyData(Repository repo, {DateTime? now}) async {
  if (await repo.hasDummyData()) return;
  final today = now ?? DateTime.now();

  const surnames = ['김', '이', '박', '최', '정', '강', '조', '윤', '장', '임'];
  const givenNames = ['민준', '서연', '도윤', '하은', '지호'];
  const amounts = [30000, 50000, 70000, 100000, 150000, 200000, 300000, 500000];
  const eventNames = {
    '결혼': '결혼식',
    '장례': '장례식',
    '돌': '돌잔치',
    '생일': '생일',
    '개업': '개업식',
    '기타': '모임',
  };

  for (var i = 0; i < 50; i++) {
    final name = '${surnames[i % 10]}${givenNames[i ~/ 10]}';
    final personId = await repo.insertPerson(Person(
      name: name,
      relation: Relations.all[i % Relations.all.length],
      phone: i.isEven ? '010-${1000 + i}-${5000 + i}' : null,
      memo: dummyDataMarker,
      createdAt: today,
    ));

    // 올해부터 5년 전까지 해마다, 1~12월이 고르게 섞이도록 흩어 놓는다.
    final date =
        DateTime(today.year - i ~/ 9, (i * 5) % 12 + 1, (i * 3) % 28 + 1);
    final type = EventTypes.all[i % EventTypes.all.length];
    final isMine = i.isOdd;
    final eventId = await repo.insertEvent(Event(
      type: type,
      title: '$name ${eventNames[type]}',
      date: date,
      isMine: isMine,
      memo: dummyDataMarker,
      notify: false, // 더미 행사로 알림이 울리지 않게 한다
      personId: isMine ? null : personId,
    ));

    await repo.insertRecord(GiftRecord(
      personId: personId,
      eventId: eventId,
      direction: isMine ? Direction.received : Direction.sent,
      amount: amounts[i % amounts.length],
      method: Methods.all[i % 2],
      // 아직 오지 않은 행사의 기록은 오늘 날짜로 둔다
      date: date.isAfter(today) ? today : date,
    ));
  }
}
