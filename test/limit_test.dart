// 추가 M · P · Q: 무료 한도(사람 30명 · 내 행사 1개)를 받은 돈 적기(내 행사)와
// 내 행사가 생기는 모든 입구에 똑같이 적용한다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/providers.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/event.dart';
import 'package:gyeongjosa/models/gift_record.dart';
import 'package:gyeongjosa/models/person.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/screens/event_detail_screen.dart';
import 'package:gyeongjosa/screens/event_form_screen.dart';
import 'package:gyeongjosa/screens/my_events_screen.dart';
import 'package:gyeongjosa/screens/paywall_screen.dart';
import 'package:gyeongjosa/screens/pick_my_event_screen.dart';
import 'package:gyeongjosa/screens/receive_money_screen.dart';
import 'package:gyeongjosa/screens/reception_form_screen.dart';
import 'package:gyeongjosa/screens/reception_import_screen.dart';
import 'package:gyeongjosa/screens/whose_event_screen.dart';
import 'package:gyeongjosa/services/limit_service.dart';
import 'package:gyeongjosa/services/pro_service.dart';
import 'package:gyeongjosa/services/receive_targets.dart';
import 'package:gyeongjosa/services/reception_import.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

Event _myEvent({bool settings = true, bool meals = false}) => Event(
      id: 1,
      type: '결혼',
      title: '내 결혼식',
      date: DateTime(2026, 11, 1),
      isMine: true,
      receiveSides: settings ? const ['신랑측', '신부측'] : null,
      mealTicketEnabled: meals,
      defaultMealTickets: 1,
      methodEnabled: meals,
    );

class _FakeRepository extends Repository {
  _FakeRepository(int count, {this.event, this.myEventCount = 0})
      : super(DatabaseHelper.forTest('unused.db')) {
    for (var i = 1; i <= count; i++) {
      people.add(Person(id: i, name: '기존$i', createdAt: DateTime(2026)));
    }
  }
  final people = <Person>[];
  final records = <GiftRecord>[];
  Event? event;
  int myEventCount;

  @override
  Future<List<Person>> allPeople() async => people;
  @override
  Future<List<Person>> findPeopleByExactName(String name) async =>
      people.where((p) => p.name == name).toList();
  @override
  Future<int> countPeople() async => people.length;
  @override
  Future<int> insertPerson(Person person) async {
    final id = people.length + 1;
    people.add(Person(id: id, name: person.name, createdAt: person.createdAt));
    return id;
  }

  @override
  Future<Person?> getPerson(int id) async => people[id - 1];
  @override
  Future<int> insertRecord(GiftRecord record) async {
    records.add(record);
    return records.length;
  }

  @override
  Future<Event?> getEvent(int id) async => event;
  @override
  Future<List<GiftRecord>> recordsForEvent(int eventId) async => [
        for (final (i, r) in records.indexed.toList().reversed)
          GiftRecord(
            id: i + 1,
            personId: r.personId,
            eventId: r.eventId,
            direction: r.direction,
            amount: r.amount,
            date: r.date,
            side: r.side,
            mealTickets: r.mealTickets,
            personName: people[r.personId - 1].name,
          ),
      ];
  @override
  Future<int> countMyEvents() async => myEventCount;
  @override
  Future<List<Event>> myEvents() async => [?event];
  @override
  Future<List<EventSummary>> eventSummaries() async =>
      [if (event case final e?) EventSummary(event: e, count: 0, total: 0)];
  @override
  Future<List<ReceptionSummary>> receptionSummaries() async => const [];
  @override
  Future<ImportPlan> planImport(ReceptionPackage package,
          {int? eventId, int? maxPeople}) async =>
      const ImportPlan([], 0, 0);
}

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  Future<_FakeRepository> open(WidgetTester tester, Widget home,
      {int people = 28,
      bool pro = false,
      Event? event,
      int myEvents = 0}) async {
    tester.view.physicalSize = const Size(411 * 2, 914 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'flutter.${PrefKeys.restorePromptDone}': true,
      'flutter.${PrefKeys.devProOverride}': pro,
      'flutter.coach_seen_receiveMoney': true,
      'flutter.coach_seen_eventDetail': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = _FakeRepository(people,
        event: event ?? _myEvent(), myEventCount: myEvents);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        repositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: home),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> save(WidgetTester tester, String name, String amount) async {
    await tester.enterText(find.byType(TextField).first, name);
    await tester.tap(find.text(amount));
    await tester.pumpAndSettle();
  }

  const myReceive = ReceiveMoneyScreen(target: MyEventTarget(1));

  group('받은 돈 적기 > 내 행사: 사람 30명 한도', () {
    testWidgets('사람 28명이면 29 · 30번째는 저장되고 31번째에서 결제 화면', (tester) async {
      final repo = await open(tester, myReceive);
      expect(find.text('무료로 2명 더 적을 수 있어요'), findsOneWidget);
      expect(find.text('내 행사 · 내 결혼식'), findsOneWidget);

      await save(tester, '새손님1', '5만');
      await save(tester, '새손님2', '5만');
      expect(repo.people.length, 30);
      expect(find.byType(PaywallScreen), findsNothing);

      await save(tester, '새손님3', '10만');
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(repo.people.length, 30);
      expect(repo.records.length, 2);

      // 결제 화면을 닫으면 적은 이름과 금액이 그대로 남아 있다
      await tester.tap(find.text('나중에 할게요'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.text('새손님3'), findsOneWidget);
      expect(find.text('100,000'), findsOneWidget);
      expect(find.text('무료 30명이 다 찼어요. 이미 등록한 사람은 계속 적을 수 있어요'),
          findsOneWidget);
    });

    testWidgets('저장은 people + records(받음)에, 구분도 함께', (tester) async {
      final repo = await open(tester, myReceive, people: 0);
      await tester.tap(find.text('신부측'));
      await tester.pumpAndSettle();
      await save(tester, '김철수', '5만');
      final r = repo.records.single;
      expect(r.direction, '받음');
      expect(r.eventId, 1);
      expect(r.side, '신부측');
      expect(r.mealTickets, isNull);
      expect(repo.people.single.name, '김철수');
    });

    testWidgets('한도가 차도 이미 등록된 이름은 저장된다 (한도에 세지 않음)', (tester) async {
      final repo = await open(tester, myReceive, people: 30);
      await save(tester, '기존7', '5만');
      expect(find.byType(PaywallScreen), findsNothing);
      expect(repo.people.length, 30);
      expect(repo.records.single.personId, 7);
    });

    testWidgets('프로는 31번째도 결제 화면 없이 저장되고 남은 인원 안내가 없다', (tester) async {
      final repo = await open(tester, myReceive, people: 30, pro: true);
      expect(find.textContaining('무료로'), findsNothing);
      await save(tester, '새손님', '5만');
      expect(find.byType(PaywallScreen), findsNothing);
      expect(repo.people.length, 31);
    });

    testWidgets('남은 인원이 6명 이상이면 안내를 보여주지 않는다', (tester) async {
      await open(tester, myReceive, people: 24);
      expect(find.textContaining('무료로'), findsNothing);
    });
  });

  group('내 행사 상세 [받은 돈 적기]', () {
    testWidgets('설정한 행사는 질문 없이 바로 입력 화면, 식권 · 계좌 칩이 설정대로 보인다',
        (tester) async {
      await open(tester, const EventDetailScreen(eventId: 1),
          event: _myEvent(meals: true), myEvents: 1);
      expect(find.text('받은 돈 적기'), findsOneWidget);
      expect(find.text('장부 가져오기'), findsOneWidget);
      expect(find.text('장부 보내기'), findsOneWidget);
      expect(find.text('행사장 접수'), findsNothing);
      await tester.tap(find.text('받은 돈 적기'));
      await tester.pumpAndSettle();
      expect(find.byType(WhoseEventScreen), findsNothing);
      expect(find.byType(ReceiveMoneyScreen), findsOneWidget);
      expect(find.text('4+'), findsOneWidget);
      expect(find.text('계좌'), findsOneWidget);
    });

    testWidgets('식권을 끈 행사는 칩이 없다', (tester) async {
      await open(tester, const EventDetailScreen(eventId: 1), myEvents: 1);
      await tester.tap(find.text('받은 돈 적기'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiveMoneyScreen), findsOneWidget);
      expect(find.text('4+'), findsNothing);
      expect(find.text('계좌'), findsNothing);
    });

    testWidgets('설정 전인 행사는 행사 설정(구분 · 식권 · 결제 방법)을 먼저 묻는다', (tester) async {
      await open(tester, const EventDetailScreen(eventId: 1),
          event: _myEvent(settings: false), myEvents: 1);
      await tester.tap(find.text('받은 돈 적기'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceptionFormScreen), findsOneWidget);
      expect(find.text('내 행사 · 내 결혼식'), findsOneWidget);
      // 행사 이름 · 받는 사람은 묻지 않는다
      expect(find.text('행사 이름'), findsNothing);
      expect(find.text('받는 사람 이름'), findsNothing);
      expect(find.text('받기 시작'), findsOneWidget);
    });
  });

  group('내 행사가 생기는 입구: 누르는 순간 결제 화면 (내 행사 1개 · 무료)', () {
    testWidgets('내 행사 탭 [내 행사 만들기]에 자물쇠 · 프로 표시, 누르면 바로 결제 화면',
        (tester) async {
      await open(tester, const MyEventsScreen(), myEvents: 1);
      expect(find.text('프로'), findsOneWidget);
      await tester.tap(find.text('내 행사 만들기'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.byType(EventFormScreen), findsNothing);
      await tester.tap(find.text('나중에 할게요'));
      await tester.pumpAndSettle();
      expect(find.byType(MyEventsScreen), findsOneWidget);
    });

    testWidgets('받은 돈 적기 > 내 행사 [+ 새 내 행사]도 같다', (tester) async {
      await open(tester, const PickMyEventScreen(), myEvents: 1);
      expect(find.text('어느 행사에 적을까요?'), findsOneWidget);
      expect(find.text('프로'), findsOneWidget);
      await tester.tap(find.text('새 내 행사'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.byType(EventFormScreen), findsNothing);
    });

    testWidgets('장부 가져오기 · 내 행사로 옮기기의 새 내 행사 만들기도 같다', (tester) async {
      await open(
          tester,
          ReceptionImportScreen(
            package: ReceptionPackage(
              Reception(
                id: 'r1',
                title: '내 결혼식',
                eventType: '결혼',
                date: DateTime(2026, 11, 1),
                sides: const ['신랑측'],
                operatorName: '',
                startedAt: DateTime(2026, 11, 1),
              ),
              const [],
            ),
          ),
          myEvents: 1);
      expect(find.text('프로'), findsOneWidget);
      await tester.tap(find.text('새 내 행사 만들기'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
    });

    testWidgets('내 행사가 없으면 자물쇠가 없고 바로 만들기 화면', (tester) async {
      final repo = await open(tester, const WhoseEventScreen());
      repo.event = null;
      await tester.tap(find.text('내 행사'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.byType(EventFormScreen), findsOneWidget);
    });
  });

  testWidgets('내 행사 만들기 화면에는 대신 받기 안내가 없다', (tester) async {
    await open(tester, const EventFormScreen(initialIsMine: true));
    expect(find.textContaining('대신 받나요'), findsNothing);
    expect(find.textContaining('행사장 접수'), findsNothing);
  });

  group('한도 상태 (테스트 메뉴)', () {
    Future<ProviderContainer> make(Map<String, Object> prefsValues) async {
      SharedPreferences.setMockInitialValues(
          {for (final e in prefsValues.entries) 'flutter.${e.key}': e.value});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(prefs),
        repositoryProvider.overrideWithValue(_FakeRepository(31)),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('스위치를 끄면 실제 구매가 없을 때 무료로 본다', () async {
      final c = await make({PrefKeys.devProOverride: false});
      final status = await c.read(limitStatusProvider.future);
      expect(status.isPro, isFalse);
      expect(status.basis, '테스트 스위치');
      expect(status.people, 31);
      expect(status.summary, contains('사람 31명 / 무료 30명'));
    });

    test('스위치를 쓰지 않으면 실제 구매 여부를 따른다', () async {
      final none = await make({});
      expect((await none.read(limitStatusProvider.future)).basis, '구매 없음');
      expect(none.read(isProProvider), isFalse);
      final bought = await make({PrefKeys.proPurchased: true});
      expect((await bought.read(limitStatusProvider.future)).basis,
          'Google Play 구매');
      expect(bought.read(isProProvider), isTrue);
    });

    test('구매 기록이 있어도 스위치를 끄면 무료로 본다', () async {
      final c = await make(
          {PrefKeys.proPurchased: true, PrefKeys.devProOverride: false});
      expect(c.read(isProProvider), isFalse);
    });
  });
}
