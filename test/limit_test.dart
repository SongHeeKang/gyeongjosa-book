// 추가 M: 무료 한도(사람 30명)를 받은 명단 직접 입력에도 똑같이 적용한다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/providers.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/event.dart';
import 'package:gyeongjosa/models/gift_record.dart';
import 'package:gyeongjosa/models/person.dart';
import 'package:gyeongjosa/screens/event_form_screen.dart';
import 'package:gyeongjosa/screens/paywall_screen.dart';
import 'package:gyeongjosa/screens/quick_entry_screen.dart';
import 'package:gyeongjosa/screens/reception_form_screen.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _event = Event(
    id: 1, type: '결혼', title: '내 결혼식', date: DateTime(2026, 11, 1), isMine: true);

class _FakeRepository extends Repository {
  _FakeRepository(int count) : super(DatabaseHelper.forTest('unused.db')) {
    for (var i = 1; i <= count; i++) {
      people.add(Person(id: i, name: '기존$i', createdAt: DateTime(2026)));
    }
  }
  final people = <Person>[];
  final records = <GiftRecord>[];

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
  Future<Event?> getEvent(int id) async => _event;
  @override
  Future<List<GiftRecord>> recordsForEvent(int eventId) async => records;
  @override
  Future<int> countMyEvents() async => 0;
}

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  Future<_FakeRepository> open(WidgetTester tester, Widget home,
      {int people = 28, bool pro = false}) async {
    tester.view.physicalSize = const Size(411 * 2, 914 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'flutter.${PrefKeys.restorePromptDone}': true,
      'flutter.${PrefKeys.devProOverride}': pro,
      'flutter.coach_seen_quickEntry': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = _FakeRepository(people);
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

  group('받은 명단 직접 입력', () {
    testWidgets('사람 28명이면 29 · 30번째는 저장되고 31번째에서 결제 화면', (tester) async {
      final repo = await open(tester, QuickEntryScreen(event: _event));
      expect(find.text('무료로 2명 더 적을 수 있어요'), findsOneWidget);

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

    testWidgets('한도가 차도 이미 등록된 이름은 저장된다 (한도에 세지 않음)', (tester) async {
      final repo = await open(tester, QuickEntryScreen(event: _event), people: 30);
      await save(tester, '기존7', '5만');
      expect(find.byType(PaywallScreen), findsNothing);
      expect(repo.people.length, 30);
      expect(repo.records.single.personId, 7);
    });

    testWidgets('프로는 31번째도 결제 화면 없이 저장되고 남은 인원 안내가 없다', (tester) async {
      final repo = await open(tester, QuickEntryScreen(event: _event), people: 30, pro: true);
      expect(find.textContaining('무료로'), findsNothing);
      await save(tester, '새손님', '5만');
      expect(find.byType(PaywallScreen), findsNothing);
      expect(repo.people.length, 31);
    });

    testWidgets('남은 인원이 6명 이상이면 안내를 보여주지 않는다', (tester) async {
      await open(tester, QuickEntryScreen(event: _event), people: 24);
      expect(find.textContaining('무료로'), findsNothing);
    });
  });

  testWidgets('내 행사 만들기에서 행사장 접수로 갈 수 있다', (tester) async {
    await open(tester, const EventFormScreen(initialIsMine: true));
    expect(find.text("다른 사람 행사의 돈을 대신 받나요? '행사장 접수'는 인원 제한 없이 무료예요"),
        findsOneWidget);
    await tester.tap(find.text('행사장 접수로 가기'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceptionFormScreen), findsOneWidget);
  });

  testWidgets('일정 추가(남의 행사)에는 행사장 접수 안내가 없다', (tester) async {
    await open(tester, const EventFormScreen());
    expect(find.text('행사장 접수로 가기'), findsNothing);
  });
}
