import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/providers.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/main.dart';
import 'package:gyeongjosa/models/event.dart';
import 'package:gyeongjosa/models/gift_record.dart';
import 'package:gyeongjosa/models/person.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/screens/event_form_screen.dart';
import 'package:gyeongjosa/screens/home_screen.dart';
import 'package:gyeongjosa/screens/main_shell.dart';
import 'package:gyeongjosa/screens/my_events_screen.dart';
import 'package:gyeongjosa/screens/onboarding_screen.dart';
import 'package:gyeongjosa/screens/paywall_screen.dart';
import 'package:gyeongjosa/screens/stats_screen.dart';
import 'package:gyeongjosa/services/format.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:gyeongjosa/widgets/app_bottom_nav.dart';
import 'package:gyeongjosa/widgets/pro_gate.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DateTime daysFromNow(int days) => dateOnly(DateTime.now()).add(Duration(days: days));

Event schedule(String title, DateTime date, {int? personId}) => Event(
    type: '결혼', title: title, date: date, isMine: false, personId: personId);

/// 실제 DB 없이 화면만 확인하는 저장소
class FakeRepository extends Repository {
  FakeRepository() : super(DatabaseHelper.forTest('unused.db'));

  List<Event> pending = [];
  List<Event> upcoming = [];
  int people = 0;
  int mine = 0;
  final inserted = <GiftRecord>[];
  final insertedPeople = <Person>[];
  final insertedEvents = <Event>[];
  final hidden = <int>[];

  @override
  Future<({int sent, int received, int sentCount, int receivedCount})> yearTotals(
          int year) async =>
      (sent: 0, received: 0, sentCount: 0, receivedCount: 0);
  @override
  Future<List<Event>> upcomingSchedules({int? limit}) async => upcoming;
  @override
  Future<List<Event>> pendingAmountEvents({int? limit}) async => pending;
  @override
  Future<int> countSchedules() async => upcoming.length + pending.length;
  @override
  Future<List<GiftRecord>> recentRecords(int limit) async => const [];
  @override
  Future<int> countRecords() async => inserted.length;
  @override
  Future<int> insertRecord(GiftRecord record) async {
    inserted.add(record);
    pending = [];
    return 1;
  }

  @override
  Future<void> hidePendingEvent(int id) async {
    hidden.add(id);
    pending = [];
  }

  @override
  Future<List<int>> recordYears() async => [DateTime.now().year];
  @override
  Future<List<({int month, int sent, int received})>> monthlyTotals(
          int year) async =>
      const [];
  @override
  Future<List<EventSummary>> eventSummaries() async => const [];
  @override
  Future<List<ReceptionSummary>> receptionSummaries() async => const [];
  @override
  Future<int> countPeople() async => people;
  @override
  Future<int> countMyEvents() async => mine;
  @override
  Future<List<Person>> allPeople() async => const [];
  @override
  Future<List<PersonSummary>> peopleSummaries() async => const [];
  @override
  Future<List<Person>> findPeopleByExactName(String name) async => const [];
  @override
  Future<int> insertPerson(Person person) async {
    insertedPeople.add(person);
    return 7;
  }

  @override
  Future<int> insertEvent(Event event) async {
    insertedEvents.add(event);
    return 9;
  }

  @override
  Future<Event?> getEvent(int id) async => insertedEvents.isEmpty
      ? null
      : Event(
          id: id,
          type: insertedEvents.last.type,
          title: insertedEvents.last.title,
          date: insertedEvents.last.date,
          isMine: insertedEvents.last.isMine,
          notify: false,
          personId: insertedEvents.last.personId);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUpAll(() => initializeDateFormatting('ko_KR'));

  group('DB', () {
    late Directory dir;
    late Repository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('structure_test');
      repo = Repository(DatabaseHelper.forTest(p.join(dir.path, 't.db')));
    });

    tearDown(() async {
      await (await databaseFactory.openDatabase(p.join(dir.path, 't.db')))
          .close();
      await dir.delete(recursive: true);
    });

    test('v3 데이터는 v4로 올려도 그대로 남는다', () async {
      final path = p.join(dir.path, 'old.db');
      final old = await databaseFactory.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 3,
            onCreate: (db, _) async {
              await db.execute(
                  "CREATE TABLE people (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, relation TEXT NOT NULL DEFAULT '기타', phone TEXT, memo TEXT, created_at TEXT NOT NULL)");
              await db.execute(
                  "CREATE TABLE events (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL DEFAULT '기타', title TEXT NOT NULL, date TEXT NOT NULL, is_mine INTEGER NOT NULL DEFAULT 0, place TEXT, memo TEXT, notify INTEGER NOT NULL DEFAULT 1)");
              await db.execute(
                  "CREATE TABLE records (id INTEGER PRIMARY KEY AUTOINCREMENT, person_id INTEGER NOT NULL, event_id INTEGER, direction TEXT NOT NULL, amount INTEGER NOT NULL, method TEXT NOT NULL DEFAULT '현금', date TEXT NOT NULL, memo TEXT)");
              await db.insert('events', {
                'title': '옛 일정',
                'date': '2026-01-01',
                'is_mine': 0,
              });
            },
          ));
      await old.close();

      final helper = DatabaseHelper.forTest(path);
      final migrated = Repository(helper);
      final pending = await migrated.pendingAmountEvents();
      expect(pending.single.title, '옛 일정');
      expect(pending.single.personId, isNull);
      expect(pending.single.pendingHidden, isFalse);
      await helper.close();
    });

    test('얼마 내셨어요: 지난 일정만, 기록이 생기거나 숨기면 사라진다', () async {
      final person = await repo.insertPerson(
          Person(name: '김철수', relation: '친구', createdAt: DateTime.now()));
      final past = await repo
          .insertEvent(schedule('김철수 결혼식', daysFromNow(-1), personId: person));
      final hide = await repo
          .insertEvent(schedule('이영희 결혼식', daysFromNow(-2), personId: person));
      await repo.insertEvent(schedule('오늘 일정', daysFromNow(0)));
      await repo.insertEvent(Event(
          type: '결혼', title: '내 결혼식', date: daysFromNow(-3), isMine: true));

      var pending = await repo.pendingAmountEvents();
      expect(pending.map((e) => e.title), ['김철수 결혼식', '이영희 결혼식']);
      expect(pending.first.personRelation, '친구');

      await repo.insertRecord(GiftRecord(
          personId: person,
          eventId: past,
          direction: '보냄',
          amount: 50000,
          date: daysFromNow(-1)));
      await repo.hidePendingEvent(hide);
      expect(await repo.pendingAmountEvents(), isEmpty);
      // 숨겨도 일정 자체는 남는다
      expect(await repo.getEvent(hide), isNotNull);
    });

    test('다가오는 일정에는 내 행사가 나오지 않는다', () async {
      await repo.insertEvent(schedule('남의 행사', daysFromNow(3)));
      await repo.insertEvent(Event(
          type: '결혼', title: '내 결혼식', date: daysFromNow(3), isMine: true));
      expect((await repo.upcomingSchedules()).map((e) => e.title), ['남의 행사']);
      expect((await repo.myEvents()).map((e) => e.title), ['내 결혼식']);
    });

    test('사람을 지워도 일정은 남고 연결만 끊긴다', () async {
      final person = await repo.insertPerson(
          Person(name: '김철수', relation: '친구', createdAt: DateTime.now()));
      final id = await repo
          .insertEvent(schedule('김철수 결혼식', daysFromNow(3), personId: person));
      await repo.deletePerson(person);
      expect((await repo.getEvent(id))!.personId, isNull);
    });
  });

  test('일정 이름은 이름과 종류로 만든다', () {
    expect(Event.scheduleTitle('김철수', '결혼'), '김철수 결혼식');
    expect(Event.scheduleTitle('김철수', '기타'), '김철수');
  });

  group('화면', () {
    Future<FakeRepository> pump(WidgetTester tester, Widget home,
        {FakeRepository? repository}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(
          {'flutter.${PrefKeys.notifPermissionAsked}': true});
      final prefs = await SharedPreferences.getInstance();
      final repo = repository ?? FakeRepository();
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

    testWidgets('탭은 4개이고, 모든 탭 같은 자리에 기록하기 버튼이 있다', (tester) async {
      await pump(tester, const MainShell());
      expect(find.text('장부'), findsNothing);
      final labels = [
        for (final widget in tester.widgetList<Text>(find.descendant(
            of: find.byType(AppBottomNav), matching: find.byType(Text))))
          widget.data,
      ];
      expect(labels, ['홈', '사람', '내 행사', '통계']);

      final position = tester.getCenter(find.text('기록하기'));
      for (final tab in ['사람', '내 행사', '통계', '홈']) {
        await tester.tap(find.descendant(
            of: find.byType(AppBottomNav), matching: find.text(tab)));
        await tester.pumpAndSettle();
        expect(find.text('기록하기'), findsOneWidget);
        expect(tester.getCenter(find.text('기록하기')), position);
      }
    });

    testWidgets('통계 탭: 선택되면 채운 아이콘 · 포인트색 · 굵은 라벨, 월별과 프로 잠금이 그대로', (tester) async {
      await pump(tester, const MainShell());
      final nav = find.byType(AppBottomNav);
      await tester.tap(
          find.descendant(of: nav, matching: find.text('통계')));
      await tester.pumpAndSettle();

      final label = tester.widget<Text>(
          find.descendant(of: nav, matching: find.text('통계')));
      expect(label.style!.color, AppColors.primary);
      expect(label.style!.fontWeight, FontWeight.w700);
      final loader = tester
          .widget<SvgPicture>(find.descendant(of: nav, matching: find.byType(SvgPicture)).last)
          .bytesLoader as SvgAssetLoader;
      expect(loader.assetName, 'assets/icons/chart_filled.svg');

      expect(find.byType(StatsScreen), findsOneWidget);
      final locked = find.descendant(
          of: find.byType(StatsScreen),
          matching: find.byType(ProBadge, skipOffstage: false),
          skipOffstage: false);
      expect(locked, findsWidgets);
    });

    testWidgets('홈의 올해 요약은 눌러도 통계로 가지 않고 통계 보기 링크가 없다', (tester) async {
      await pump(tester, const HomeScreen());
      expect(find.text('통계 보기'), findsNothing);
      await tester.tap(find.text('보낸 마음'));
      await tester.pumpAndSettle();
      expect(find.byType(StatsScreen), findsNothing);
    });

    testWidgets('기록하기를 누르면 선택지 4개가 보인다', (tester) async {
      await pump(tester, const MainShell());
      await tester.tap(find.text('기록하기'));
      await tester.pumpAndSettle();
      for (final t in ['보냈어요', '일정 추가', '받은 돈 정리', '행사장 접수']) {
        expect(find.text(t), findsOneWidget);
      }
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('보냈어요'), findsNothing);
    });

    testWidgets('내 행사 탭에는 남의 행사 섹션이 없다', (tester) async {
      await pump(tester, const MyEventsScreen());
      expect(find.textContaining('남의 행사'), findsNothing);
      expect(find.text('내 행사 만들기'), findsOneWidget);
    });

    testWidgets('빈 화면 문구', (tester) async {
      await pump(tester, const HomeScreen());
      expect(find.textContaining("'+ 기록하기'를 눌러 첫 기록을 남겨보세요"), findsOneWidget);
      expect(find.byIcon(Icons.south_east), findsOneWidget);

      await pump(tester, const MyEventsScreen());
      expect(find.text('결혼식 · 돌잔치처럼 내가 받는 행사를 만들어 보세요'), findsOneWidget);
    });

    testWidgets('가이드: 건너뛰면 다시 뜨지 않고, 마지막 장에 시작하기가 있다', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final widget = ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(FakeRepository()),
        ],
        child: const GyeongjosaApp(),
      );
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      expect(find.text('주고받은 마음, 잊지 않게'), findsOneWidget);
      expect(find.text('시작하기'), findsNothing);
      expect(find.text('건너뛰기'), findsOneWidget);

      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('+ 버튼 하나면 돼요'), findsOneWidget);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('기록은 내 폰에만'), findsOneWidget);
      expect(find.text('건너뛰기'), findsOneWidget);

      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();
      expect(find.byType(MainShell), findsOneWidget);
      expect(prefs.getBool(PrefKeys.onboardingSeen), isTrue);

      // 앱을 다시 켠 것과 같은 상황: 가이드 없이 바로 시작
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(FakeRepository()),
        ],
        child: const GyeongjosaApp(),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('얼마 내셨어요: 금액을 누르면 일정에 연결된 보냄 기록이 생기고 사라진다',
        (tester) async {
      final repo = FakeRepository()
        ..pending = [
          Event(
              id: 3,
              type: '결혼',
              title: '김철수 결혼식',
              date: daysFromNow(-1),
              isMine: false,
              personId: 5),
        ];
      await pump(tester, const HomeScreen(), repository: repo);
      expect(find.text('얼마 내셨어요?'), findsOneWidget);

      await tester.tap(find.text('10만'));
      await tester.pumpAndSettle();
      expect(repo.inserted.single.personId, 5);
      expect(repo.inserted.single.eventId, 3);
      expect(repo.inserted.single.direction, '보냄');
      expect(repo.inserted.single.amount, 100000);
      expect(find.text('얼마 내셨어요?'), findsNothing);
    });

    testWidgets('얼마 내셨어요: 안 갔어요를 누르면 숨긴다', (tester) async {
      final repo = FakeRepository()
        ..pending = [
          Event(
              id: 3,
              type: '결혼',
              title: '김철수 결혼식',
              date: daysFromNow(-1),
              isMine: false,
              personId: 5),
        ];
      await pump(tester, const HomeScreen(), repository: repo);
      await tester.tap(find.text('안 갔어요'));
      await tester.pumpAndSettle();
      expect(repo.hidden, [3]);
      expect(repo.inserted, isEmpty);
      expect(find.text('얼마 내셨어요?'), findsNothing);
    });

    testWidgets('기록이 20개 이상이고 백업을 안 했으면 홈 위에 백업 배너가 보인다', (tester) async {
      final repo = FakeRepository()
        ..inserted.addAll(List.generate(
            20,
            (_) => GiftRecord(
                personId: 1,
                direction: '보냄',
                amount: 1000,
                date: DateTime(2026))));
      await pump(tester, const HomeScreen(), repository: repo);
      expect(find.text('백업해 두면 폰을 바꿔도 기록이 안전해요'), findsOneWidget);
    });

    testWidgets('일정 추가: 금액 없이 사람과 일정이 함께 만들어진다', (tester) async {
      final repo = await pump(tester, const EventFormScreen());
      expect(find.text('일정 추가'), findsOneWidget);
      expect(find.textContaining('금액'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '김철수');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('저장'));
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(repo.insertedPeople.single.name, '김철수');
      final event = repo.insertedEvents.single;
      expect(event.title, '김철수 결혼식');
      expect(event.isMine, isFalse);
      expect(event.personId, 7);
    });

    testWidgets('일정 추가: 무료 30명이 차면 결제 화면이 뜨고, 닫으면 저장하지 않는다',
        (tester) async {
      final repo = FakeRepository()..people = 30;
      await pump(tester, const EventFormScreen(), repository: repo);
      await tester.enterText(find.byType(TextField).first, '김철수');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('저장'));
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);

      await tester.ensureVisible(find.text('나중에 할게요'));
      await tester.tap(find.text('나중에 할게요'));
      await tester.pumpAndSettle();
      expect(repo.insertedPeople, isEmpty);
      expect(repo.insertedEvents, isEmpty);
    });

    testWidgets('두 번째 내 행사를 만들면 결제 화면이 뜨고, 남의 일정은 막지 않는다',
        (tester) async {
      final repo = FakeRepository()..mine = 1;
      await pump(tester, const EventFormScreen(initialIsMine: true),
          repository: repo);
      await tester.enterText(find.byType(TextField).first, '돌잔치');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('저장'));
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text('무료 버전은 내 행사를 1개까지 만들 수 있어요.'), findsOneWidget);
      expect(repo.insertedEvents, isEmpty);
    });
  });
}
