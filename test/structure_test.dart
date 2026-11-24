import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/screens/event_detail_screen.dart';
import 'package:gyeongjosa/services/reminder_format.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/dummy_data.dart';
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
import 'package:gyeongjosa/services/notification_service.dart';
import 'package:gyeongjosa/screens/my_events_screen.dart';
import 'package:gyeongjosa/screens/onboarding_screen.dart';
import 'package:gyeongjosa/screens/paywall_screen.dart';
import 'package:gyeongjosa/screens/stats_screen.dart';
import 'package:gyeongjosa/services/format.dart';
import 'package:gyeongjosa/screens/people_screen.dart';
import 'package:gyeongjosa/screens/settings_screen.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:gyeongjosa/services/app_config.dart';
import 'package:gyeongjosa/widgets/backup_guide.dart';
import 'package:gyeongjosa/widgets/collapsible_section.dart';
import 'package:gyeongjosa/widgets/person_form_sheet.dart';
import 'package:gyeongjosa/widgets/test_id.dart';
import 'package:gyeongjosa/screens/all_schedules_screen.dart';
import 'package:gyeongjosa/widgets/app_bottom_nav.dart';
import 'package:gyeongjosa/widgets/common.dart';
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

  // 추가 AC: 홈 '일정' 달력 · 다가오는 내 행사 · 다른 사람 행사
  List<Event> upcomingMine = [];
  List<Reception> upcomingReceptions = [];
  List<GiftRecord> calendarRecords = [];
  List<Event> calendarEvents = [];
  @override
  Future<List<Event>> upcomingMyEvents() async => upcomingMine;
  @override
  Future<List<Event>> allEvents() async => [...upcoming, ...pending];
  @override
  Future<List<Reception>> receptionsBetween(DateTime start, DateTime? end) async =>
      upcomingReceptions
          .where((r) => !r.date.isBefore(start) && (end == null || !r.date.isAfter(end)))
          .toList();
  @override
  Future<List<GiftRecord>> recordsBetween(DateTime start, DateTime end) async =>
      calendarRecords
          .where((r) => !r.date.isBefore(start) && !r.date.isAfter(end))
          .toList();
  @override
  Future<List<Event>> eventsBetween(DateTime start, DateTime end) async =>
      calendarEvents
          .where((e) => !e.date.isBefore(start) && !e.date.isAfter(end))
          .toList();
  FakeRepository() : super(DatabaseHelper.forTest('unused.db'));

  List<Event> pending = [];
  List<Event> upcoming = [];

  @override
  Future<bool> hasAnyData() async => true;

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
  /// 올해 월별 보낸 금액 (홈 '최근 6개월' · 통계 탭)
  Map<int, int> sentByMonth = {};
  @override
  Future<List<({int month, int sent, int received})>> monthlyTotals(
          int year) async =>
      List.generate(
          12,
          (i) => (
                month: i + 1,
                sent: year == DateTime.now().year ? sentByMonth[i + 1] ?? 0 : 0,
                received: 0,
              ));
  @override
  Future<List<int>> recordYears() async => [DateTime.now().year];
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
  Future<List<PersonSummary>> peopleSummaries() async => summaries;
  List<PersonSummary> summaries = [];
  @override
  Future<List<Person>> findPeopleByExactName(String name) async => const [];
  @override
  Future<int> insertPerson(Person person) async {
    insertedPeople.add(person);
    return 7;
  }

  @override
  Future<int> insertEvent(Event event, {int? maxMyEvents}) async {
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
          reminderDays: null,
          personId: insertedEvents.last.personId);
}

Finder byTestIdFinder(String id) =>
    find.byWidgetPredicate((w) => w is TestId && w.id == id);

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

    test('더미 데이터: 50개씩 들어가고, 끄면 직접 넣은 기록은 남고 더미만 지워진다', () async {
      final real = await repo.insertPerson(
          Person(name: '진짜사람', relation: '친구', createdAt: DateTime.now()));
      final realEvent = await repo.insertEvent(Event(
          type: '결혼',
          title: '진짜행사',
          date: DateTime(2026, 1, 1),
          isMine: true,
          reminderDays: null));
      await repo.insertRecord(GiftRecord(
          personId: real,
          eventId: realEvent,
          direction: '받음',
          amount: 50000,
          date: DateTime(2026, 1, 1)));
      expect(await repo.hasDummyData(), isFalse);

      final now = DateTime(2026, 11, 6);
      await insertDummyData(repo, now: now);
      await insertDummyData(repo, now: now); // 두 번 눌러도 늘어나지 않는다
      expect(await repo.hasDummyData(), isTrue);
      expect(await repo.countPeople(), 51);
      expect(await repo.countRecords(), 51);
      final events = (await repo.eventSummaries()).map((s) => s.event).toList();
      expect(events.length, 51);

      // 이름은 겹치지 않고, 연도와 월이 고르게 섞여 있다
      final people = await repo.allPeople();
      expect(people.map((p) => p.name).toSet().length, 51);
      final dummy = events.where((e) => e.title != '진짜행사');
      expect(dummy.map((e) => e.date.year).toSet().length, greaterThanOrEqualTo(5));
      expect(dummy.map((e) => e.date.month).toSet().length, 12);
      // 보냄과 받음이 모두 있고, 행사 알림은 울리지 않으며 '얼마 내셨어요?'도 뜨지 않는다
      final records = await repo.allRecords();
      expect(records.where((r) => r.direction == '보냄').length, 25);
      expect(records.where((r) => r.direction == '받음').length, 26);
      expect(dummy.every((e) => !e.hasReminder), isTrue);
      expect(await repo.pendingAmountEvents(), isEmpty);

      await repo.deleteDummyData();
      expect(await repo.hasDummyData(), isFalse);
      expect(await repo.countPeople(), 1);
      expect(await repo.countRecords(), 1);
      expect((await repo.eventSummaries()).single.event.title, '진짜행사');
      expect((await repo.allPeople()).single.name, '진짜사람');
    });

    test('추가 W: 저장 순간 내 행사 한도 — 동시에 두 번 저장해도 하나만, 지우면 다시 무료', () async {
      Event mine(String t) => Event(
          type: '결혼', title: t, date: DateTime(2026, 10, 11), isMine: true);
      // 다른 사람 행사 · 남의 행사(일정)는 세지 않는다
      await repo.insertEvent(Event(
          type: '결혼', title: '남의 행사', date: DateTime(2026, 12, 1), isMine: false),
          maxMyEvents: 1);
      // 버튼을 빠르게 두 번 누른 것처럼 동시에 저장
      final results = await Future.wait([
        repo.insertEvent(mine('첫째'), maxMyEvents: 1).then<Object>((v) => v,
            onError: (Object e) => e),
        repo.insertEvent(mine('둘째'), maxMyEvents: 1).then<Object>((v) => v,
            onError: (Object e) => e),
      ]);
      expect(results.whereType<MyEventLimitReached>().length, 1);
      expect(await repo.countMyEvents(), 1);
      // 프로(한도 없음)는 통과
      final pro = await repo.insertEvent(mine('프로'));
      expect(await repo.countMyEvents(), 2);
      // 이미 있는 내 행사 2개는 그대로 고칠 수 있다
      final e = (await repo.getEvent(pro))!;
      await repo.updateEvent(
          Event(id: e.id, type: e.type, title: '프로 고침', date: e.date, isMine: true),
          maxMyEvents: 1);
      expect((await repo.getEvent(pro))!.title, '프로 고침');
      // 남의 행사를 내 행사로 바꾸는 것은 막힌다
      final other = (await repo.eventSummaries())
          .firstWhere((s) => !s.event.isMine)
          .event;
      await expectLater(
          repo.updateEvent(
              Event(id: other.id, type: other.type, title: other.title,
                  date: other.date, isMine: true),
              maxMyEvents: 1),
          throwsA(isA<MyEventLimitReached>()));
      expect((await repo.getEvent(other.id!))!.isMine, isFalse);
      // 내 행사를 모두 지우면 다시 무료로 하나
      for (final s in (await repo.eventSummaries()).where((s) => s.event.isMine)) {
        await repo.deleteEvent(s.event.id!);
      }
      await repo.insertEvent(mine('다시'), maxMyEvents: 1);
      expect(await repo.countMyEvents(), 1);
    });

    test('v3 데이터는 최신 버전으로 올려도 그대로 남는다', () async {
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
              await db.execute(
                  "CREATE TABLE receptions (id TEXT PRIMARY KEY, title TEXT NOT NULL, event_type TEXT NOT NULL DEFAULT '기타', date TEXT NOT NULL, sides TEXT NOT NULL, operator_name TEXT NOT NULL DEFAULT '', started_at TEXT NOT NULL, finished_at TEXT, imported INTEGER NOT NULL DEFAULT 0)");
              await db.execute(
                  "CREATE TABLE reception_entries (id TEXT PRIMARY KEY, reception_id TEXT NOT NULL, name TEXT NOT NULL, amount INTEGER NOT NULL, side TEXT NOT NULL DEFAULT '', method TEXT NOT NULL DEFAULT '현금', meal_tickets INTEGER NOT NULL DEFAULT 1, memo TEXT, created_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)");
              await db.insert('events', {
                'title': '옛 일정',
                'date': '2026-01-01',
                'is_mine': 0,
              });
              // 추가 AC: '전날 알림' 꺼진 일정 (켜진 것은 위 '옛 일정', notify 기본 1)
              await db.insert('events', {
                'title': '알림 끈 일정',
                'date': '2025-12-01',
                'is_mine': 0,
                'notify': 0,
              });
              await db.insert('receptions', {
                'id': 'old',
                'title': '옛 접수',
                'date': '2026-01-01',
                'sides': '["신랑측"]',
                'started_at': '2026-01-01T09:00:00',
              });
            },
          ));
      await old.close();

      final helper = DatabaseHelper.forTest(path);
      final migrated = Repository(helper);
      final pending = await migrated.pendingAmountEvents();
      expect(pending.map((e) => e.title), ['옛 일정', '알림 끈 일정']);
      expect(pending.first.personId, isNull);
      expect(pending.first.pendingHidden, isFalse);
      // 추가 AC(v8): '전날 알림' 켜진 일정 → 1일 전 오전 9시, 꺼진 일정 → 없음
      expect(pending.first.reminderDays, 1);
      expect(pending.first.reminderHour, 9);
      expect(pending.last.reminderDays, isNull);
      expect(pending.last.hasReminder, isFalse);
      // 예전 접수는 전처럼 식권과 결제 방법이 모두 켜진 채로 남는다
      final oldReception = (await migrated.receptionSummaries()).single.reception;
      expect(oldReception.title, '옛 접수');
      expect(oldReception.mealTicketEnabled, isTrue);
      expect(oldReception.defaultMealTickets, 1);
      expect(oldReception.methodEnabled, isTrue);
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
      expect(labels, ['홈', '사람', '행사', '통계']);

      final position = tester.getCenter(find.byType(RecordFab));
      for (final tab in ['사람', '행사', '통계', '홈']) {
        await tester.tap(find.descendant(
            of: find.byType(AppBottomNav), matching: find.text(tab)));
        await tester.pumpAndSettle();
        expect(find.byTooltip('기록하기'), findsOneWidget);
        expect(tester.getCenter(find.byType(RecordFab)), position);
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

    testWidgets('모든 탭 오른쪽 위 같은 자리에 설정 아이콘이 있다', (tester) async {
      await pump(tester, const MainShell());
      final position = tester.getCenter(find.byTooltip('설정'));
      for (final tab in ['사람', '행사', '통계']) {
        await tester.tap(find.descendant(
            of: find.byType(AppBottomNav), matching: find.text(tab)));
        await tester.pumpAndSettle();
        expect(find.byTooltip('설정'), findsOneWidget, reason: tab);
        expect(tester.getCenter(find.byTooltip('설정')), position, reason: tab);
      }
    });

    testWidgets('기록하기를 누르면 선택지 3개가 보인다', (tester) async {
      await pump(tester, const MainShell());
      await tester.tap(find.byTooltip('기록하기'));
      await tester.pumpAndSettle();
      for (final t in ['보냈어요', '일정 추가', '행사 장부 작성']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.text('행사장 접수'), findsNothing);
      expect(find.text('받은 명단 직접 입력'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('보냈어요'), findsNothing);
    });

    testWidgets('행사 탭에는 남의 행사 섹션이 없다', (tester) async {
      await pump(tester, const MyEventsScreen());
      expect(find.textContaining('남의 행사'), findsNothing);
      // 빈 화면: 홈 '다가오는 일정이 없어요'와 같은 EmptyView. 가져오기 링크도 없음(추가 X)
      expect(find.text('아직 행사가 없어요.'), findsOneWidget);
      expect(find.text('연필 버튼 > 행사 장부 작성에서 만들어요'), findsOneWidget);
      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('행사를 추가해 주세요'), findsNothing);
      expect(find.text('+ 추가'), findsNothing);
      expect(find.textContaining('가져오기'), findsNothing);
      expect(find.textContaining('붙여넣'), findsNothing);
      expect(find.text('행사 만들기'), findsNothing);
      expect(find.text('받은 장부 가져오기'), findsNothing);
    });

    testWidgets('빈 화면 문구', (tester) async {
      await pump(tester, const HomeScreen());
      expect(find.textContaining('오른쪽 아래 연필 버튼을 눌러 첫 기록을 남겨보세요'), findsOneWidget);

      // 연필 버튼을 가리키던 파란 화살표는 없앴다 (추가 X)
      await pump(tester, const MainShell());
      expect(find.byIcon(Icons.south), findsNothing);

      await pump(tester, const MyEventsScreen());
      expect(find.text('아직 행사가 없어요.'), findsOneWidget);
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
      expect(find.text('연필 버튼 하나면 돼요'), findsOneWidget);
      expect(find.text('보냈어요 · 일정 추가 · 행사 장부 작성'), findsOneWidget);
      // 그림은 카드 3개
      for (final t in ['보냈어요', '일정 추가', '행사 장부 작성']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();

      // 새 3장: 접수 안내 그림
      expect(tester.takeException(), isNull);
      expect(find.text('내 행사도, 다른 사람 행사도'), findsOneWidget);
      expect(
          find.text(
              '손님 이름을 적고 금액만 누르면 저장돼요. 끝나면 장부를 글자로 보내요'),
          findsOneWidget);
      for (final t in [
        '42명 · 3,150,000원',
        '신랑측 ▾',
        '김민수',
        '이서연 · 10만 · 오후 12:34',
        '박민수 · 5만 · 오후 12:33',
        '되돌리기',
        '5만',
        '10만',
        '15만',
        '20만',
        '25만',
        '30만',
        '50만',
        '100만',
        '이름 입력',
        '금액 탭',
        '장부 보내기',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('시작하기'), findsNothing);
      expect(find.text('건너뛰기'), findsOneWidget);

      // 추가 X: 백업 장은 숨겨 4장이 마지막
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('기록은 내 폰에만'), findsOneWidget);
      expect(find.text('건너뛰기'), findsOneWidget);
      expect(find.text('기록은 이 폰에만 저장돼요'), findsNothing);
      expect(onboardingPageCount(), 4);

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

    testWidgets('kShowHomeBackup = true면 가이드 마지막(5장)이 백업 장', (tester) async {
      expect(onboardingPageCount(showBackup: true), 5);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
            theme: buildAppTheme(),
            home: const OnboardingScreen(replay: true, showBackup: true)),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('다음'));
        await tester.pumpAndSettle();
      }
      expect(find.text('기록은 이 폰에만 저장돼요'), findsOneWidget);
      expect(find.text('시작하기'), findsOneWidget);
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

      await tester.tap(find.text('10만').first); // 아래 '최근 6개월' 눈금에도 10만이 있다
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

    testWidgets('홈은 기록이 없어도 요약 · 다가오는 일정 · 최근 6개월(빈 틀) · 최근 기록 순서, 화살표 없음',
        (tester) async {
      await pump(tester, const MainShell());
      // 추가 AC: 일정 달력이 생겨 홈이 길어졌다. 한 화면에 모두 보이게 키워서 순서를 본다
      tester.view.physicalSize = const Size(1080, 4200);
      await tester.pumpAndSettle();
      expect(find.text('보낸 마음'), findsOneWidget);
      expect(find.text('다가오는 일정이 없어요.'), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_all_schedules')), findsNothing);
      expect(find.text('전체 보기'), findsNothing);
      expect(find.text('최근 6개월'), findsOneWidget);
      expect(find.text('기록이 생기면 여기에 보여요'), findsNothing); // 추가 AC: 빈 그래프에 문구 없음
      expect(find.text('${DateTime.now().month}월'), findsOneWidget);
      expect(find.text('통계 ›'), findsOneWidget);
      expect(find.text('보냄'), findsNWidgets(2)); // 범례 (일정 달력 · 최근 6개월)
      expect(find.textContaining('첫 기록을 남겨보세요'), findsOneWidget);
      expect(find.byIcon(Icons.south), findsNothing);
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      // 추가 AC: '다가오는 일정' 섹션은 '일정'(달력 + 다가오는 일정)
      expect(y('보낸 마음'), lessThan(y('일정')));
      expect(y('일정'), lessThan(y('최근 6개월')));
      expect(y('최근 6개월'), lessThan(y('최근 기록')));
    });

    testWidgets('홈 \'최근 6개월\': 기록이 있으면 막대, 일정과 최근 기록 사이, 누르면 통계 탭',
        (tester) async {

      final repo = FakeRepository()
        ..sentByMonth = {DateTime.now().month: 70000}
        ..upcoming = [
          Event(id: 7, type: '결혼', title: '철수 결혼식',
              date: DateTime.now().add(const Duration(days: 3)), isMine: false),
        ];
      await pump(tester, const MainShell(), repository: repo);
      tester.view.physicalSize = const Size(1080, 4200); // 홈 전체가 한 화면에 보이게
      await tester.pumpAndSettle();
      expect(find.text('최근 6개월'), findsOneWidget);
      expect(find.text('기록이 생기면 여기에 보여요'), findsNothing);
      expect(find.text('${DateTime.now().month}월'), findsOneWidget);
      double top(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(tester.getTopLeft(find.text('일정').first).dy,
          lessThan(top('최근 6개월')));
      expect(top('최근 6개월'), lessThan(top('최근 기록')));
      // 보냄 막대는 코랄, 받음은 파랑
      expect(AppColors.chartSent, AppColors.sent);
      expect(AppColors.sent, const Color(0xFFD85A30));

      await tester.tap(find.text('통계 ›'));
      await tester.pumpAndSettle();
      expect(find.text('월별 보냄 · 받음'), findsOneWidget);
    });

    // ───────── 추가 AC: 홈 '일정' (달력 + 다가오는 일정) ─────────
    DateTime inDays(int n) {
      final t = DateTime.now();
      return DateTime(t.year, t.month, t.day + n);
    }

    testWidgets('다가오는 일정: 일정 · 내 행사 · 다른 사람 행사를 날짜순으로, D-n과 라벨, 알림 켠 일정에 종',
        (tester) async {
      final repo = FakeRepository()
        ..upcoming = [
          Event(id: 3, type: '결혼', title: '임원택 결혼식', date: inDays(12),
              isMine: false),
        ]
        ..upcomingMine = [
          Event(id: 4, type: '돌', title: '우리 돌잔치', date: inDays(4),
              isMine: true, reminderDays: null),
        ]
        ..upcomingReceptions = [
          Reception(id: 'r', title: '누나 결혼식', eventType: '결혼',
              date: inDays(25), sides: const [], operatorName: '',
              startedAt: DateTime.now()),
        ];
      await pump(tester, const HomeScreen(), repository: repo);
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('우리 돌잔치'), lessThan(y('임원택 결혼식')));
      expect(y('임원택 결혼식'), lessThan(y('누나 결혼식')));
      for (final d in ['D-4', 'D-12', 'D-25']) {
        expect(find.text(d), findsOneWidget, reason: d);
      }
      expect(find.text('내 행사'), findsOneWidget);
      expect(find.text('다른 사람 행사'), findsOneWidget);
      // 범례의 '일정/행사'와 별개로 '일정' 라벨 칩 (섹션 제목 '일정' 포함 2개)
      expect(find.text('일정'), findsNWidgets(2));
      // 알림을 켜 둔 일정(임원택, 기본 1일 전)만 종
      expect(find.byKey(const ValueKey('upcoming_bell')), findsOneWidget);
      await tester.tap(find.text('우리 돌잔치'));
      await tester.pumpAndSettle();
      expect(find.byType(EventDetailScreen), findsOneWidget);
    });

    testWidgets('주간 띠: 점 색(보냄 코랄 · 받음 파랑 · 일정 회색), 날짜를 누르면 그날 내역, 다시 누르면 다가오는 일정',
        (tester) async {
      final today = inDays(0);
      final repo = FakeRepository()
        ..calendarRecords = [
          GiftRecord(id: 1, personId: 1, direction: '보냄', amount: 70000,
              date: today, personName: '김철수'),
          GiftRecord(id: 2, personId: 2, direction: '받음', amount: 50000,
              date: today, personName: '이영희'),
        ]
        ..calendarEvents = [
          Event(id: 9, type: '결혼', title: '오늘 결혼식', date: today,
              isMine: false),
        ];
      await pump(tester, const HomeScreen(), repository: repo);
      expect(byTestIdFinder('home_week_label'), findsOneWidget); // '11월 4주'
      final key = 'cal_day_${today.year}${'${today.month}'.padLeft(2, '0')}${'${today.day}'.padLeft(2, '0')}';
      final cell = byTestIdFinder(key);
      final dots = tester
          .widgetList<Container>(find.descendant(of: cell, matching: find.byType(Container)))
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .whereType<Color>()
          .toList();
      expect(dots, containsAll([AppColors.sent, AppColors.received, AppColors.calendarDot]));

      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(find.text(formatShortDateWithDay(today)), findsOneWidget);
      expect(find.text('김철수'), findsOneWidget);
      expect(find.text('−70,000원'), findsOneWidget);
      expect(find.text('+50,000원'), findsOneWidget);
      expect(find.text('오늘 결혼식'), findsOneWidget);
      expect(find.text('다가오는 일정이 없어요.'), findsNothing);
      // 다시 누르면 다가오는 일정
      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(find.text('김철수'), findsNothing);
      expect(find.text('다가오는 일정이 없어요.'), findsOneWidget);

      // 기록이 없는 날: 같은 주의 다른 날
      final otherDay = DateTime(today.year, today.month,
          today.day + (today.weekday % 7 == 6 ? -1 : 1));
      await tester.tap(byTestIdFinder(
          'cal_day_${otherDay.year}${'${otherDay.month}'.padLeft(2, '0')}${'${otherDay.day}'.padLeft(2, '0')}'));
      await tester.pumpAndSettle();
      expect(find.text('이 날은 기록이 없어요'), findsOneWidget);
    });

    testWidgets('추가 AD: 날짜 목록의 일정 · 행사 줄에 D±n, 지난 날도 상세로, 보냄 · 받음 금액은 오른쪽 끝 + ›',
        (tester) async {
      final today = inDays(0);
      // 이번 주 안의 다른 날 (오늘이 일요일이면 토요일, 아니면 일요일 = 지난 날)
      final other = today.weekday == DateTime.sunday
          ? inDays(6)
          : inDays(-(today.weekday % 7));
      final repo = FakeRepository()
        ..calendarRecords = [
          GiftRecord(id: 1, personId: 1, direction: '보냄', amount: 70000,
              date: other, personName: '김철수'),
        ]
        ..calendarEvents = [
          Event(id: 9, type: '결혼', title: '그날 결혼식', date: other,
              isMine: false),
        ];
      await pump(tester, const HomeScreen(), repository: repo);
      await tester.tap(byTestIdFinder(
          'cal_day_${other.year}${'${other.month}'.padLeft(2, '0')}${'${other.day}'.padLeft(2, '0')}'));
      await tester.pumpAndSettle();
      final label = dDayLabel(other);
      expect(label, other.isBefore(today) ? startsWith('D+') : startsWith('D-'));
      final dText = tester.widget<Text>(find.text(label));
      expect(dText.style?.color,
          other.isBefore(today) ? AppColors.textSub : AppColors.primary);
      // 보냄 줄: 금액이 줄 오른쪽 끝(› 바로 왼쪽)에 붙는다
      final row = byTestIdFinder('cal_record_1');
      final amount = find.descendant(of: row, matching: find.text('−70,000원'));
      final chevron =
          find.descendant(of: row, matching: find.byIcon(Icons.chevron_right));
      expect(chevron, findsOneWidget);
      expect(tester.getTopRight(amount).dx,
          closeTo(tester.getTopLeft(chevron).dx, 1));
      // 행사 줄도 › 가 있고, 눌러서 상세로 (지난 날이어도)
      final item = byTestIdFinder('cal_item_그날 결혼식');
      expect(find.descendant(of: item, matching: find.byIcon(Icons.chevron_right)),
          findsOneWidget);
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(find.byType(EventDetailScreen), findsOneWidget);
    });

    testWidgets('월 달력: 그달 합계, 상태는 저장되어 다시 열어도 월 달력, 주간으로 돌리면 주간',
        (tester) async {
      final today = inDays(0);
      final repo = FakeRepository()
        ..calendarRecords = [
          GiftRecord(id: 1, personId: 1, direction: '보냄', amount: 200000,
              date: today, personName: '김철수'),
          GiftRecord(id: 2, personId: 2, direction: '받음', amount: 50000,
              date: today, personName: '이영희'),
        ];
      await pump(tester, const HomeScreen(), repository: repo);
      await tester.tap(find.text('월 달력'));
      await tester.pumpAndSettle();
      expect(find.text('${today.year}년 ${today.month}월'), findsOneWidget);
      expect(find.text('오늘'), findsOneWidget);
      expect(byTestIdFinder('cal_month_total'), findsOneWidget);
      expect(find.textContaining('200,000원'), findsWidgets);
      expect(find.text('주간'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefKeys.homeCalendarMonth), isTrue);

      // 앱을 다시 켠 것처럼 새로 그려도 월 달력
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('주간'), findsOneWidget);
      await tester.tap(find.text('주간'));
      await tester.pumpAndSettle();
      expect(find.text('월 달력'), findsOneWidget);
      expect(prefs.getBool(PrefKeys.homeCalendarMonth), isFalse);
    });

    // 추가 Y: 홈 섹션 접기 · 펼치기
    Finder byTestId(String id) =>
        find.byWidgetPredicate((w) => w is TestId && w.id == id);
    Finder toggle(HomeSection s) => find.descendant(
        of: byTestId('${s.id}_toggle'), matching: find.byType(IconButton));
    Finder titleOf(HomeSection s) => byTestId('${s.id}_title');

    testWidgets('빈 홈: 세 섹션 모두 화살표 · 제목으로 접고 펴고, 개수는 0이라 표시 없음',
        (tester) async {
      await pump(tester, const HomeScreen());
      for (final s in HomeSection.values) {
        expect(toggle(s), findsOneWidget, reason: s.id);
      }
      expect(find.text('다가오는 일정이 없어요.'), findsOneWidget);
      await tester.tap(toggle(HomeSection.schedules));
      await tester.pumpAndSettle();
      expect(find.text('다가오는 일정이 없어요.'), findsNothing);
      expect(find.textContaining(RegExp(r'^· [0-9]')), findsNothing);
      await tester.tap(titleOf(HomeSection.schedules));
      await tester.pumpAndSettle();
      expect(find.text('다가오는 일정이 없어요.'), findsOneWidget);

      await tester.ensureVisible(toggle(HomeSection.months));
      await tester.tap(toggle(HomeSection.months));
      await tester.pumpAndSettle();
      expect(find.text('기록이 생기면 여기에 보여요'), findsNothing);
      expect(find.text('최근 6개월'), findsOneWidget);
      await tester.ensureVisible(titleOf(HomeSection.months));
      await tester.tap(titleOf(HomeSection.months));
      await tester.pumpAndSettle();
      expect(find.text('기록이 생기면 여기에 보여요'), findsNothing); // 추가 AC: 빈 그래프에 문구 없음

      await tester.ensureVisible(toggle(HomeSection.records));
      await tester.tap(toggle(HomeSection.records));
      await tester.pumpAndSettle();
      expect(find.textContaining('첫 기록을 남겨보세요'), findsNothing);
      await tester.ensureVisible(titleOf(HomeSection.records));
      await tester.tap(titleOf(HomeSection.records));
      await tester.pumpAndSettle();
      expect(find.textContaining('첫 기록을 남겨보세요'), findsOneWidget);
    });

    testWidgets('접으면 제목 옆에 개수(일정 · n개, 기록 · n건), 6개월은 개수 없음',
        (tester) async {
      final repo = FakeRepository()
        ..upcoming = [
          for (var i = 1; i <= 4; i++)
            Event(id: i, type: '결혼', title: '일정$i',
                date: DateTime.now().add(Duration(days: i)), isMine: false),
        ]
        ..inserted.addAll(List.generate(7,
            (_) => GiftRecord(personId: 1, direction: '보냄', amount: 1000,
                date: DateTime.now())));
      await pump(tester, const HomeScreen(), repository: repo);
      expect(find.text('· 4개'), findsNothing); // 펼쳐 있을 때는 없음
      for (final s in HomeSection.values) {
        await tester.ensureVisible(toggle(s));
        await tester.tap(toggle(s));
        await tester.pumpAndSettle();
      }
      expect(find.text('· 4개'), findsOneWidget);
      expect(find.text('· 7건'), findsOneWidget);
      expect(find.text('일정1'), findsNothing);
      // 6개월은 개수 없음, 링크는 그대로
      expect(find.text('통계 ›'), findsOneWidget);
      // 추가 AC: '일정 전체 보기'는 일정 목록 아래로 옮겨 접히면 같이 숨는다
      expect(find.text('일정 전체 보기'), findsNothing);
    });

    testWidgets('전체 보기 · 통계 ›는 눌러도 접히지 않고 이동한다', (tester) async {
      final repo = FakeRepository()
        ..upcoming = [
          Event(id: 1, type: '결혼', title: '철수 결혼식',
              date: DateTime.now().add(const Duration(days: 2)), isMine: false),
        ];
      await pump(tester, const MainShell(), repository: repo);
      await tester.ensureVisible(find.text('일정 전체 보기'));
      await tester.tap(find.text('일정 전체 보기'));
      await tester.pumpAndSettle();
      expect(find.byType(AllSchedulesScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('철수 결혼식'), findsOneWidget); // 접히지 않음
      await tester.ensureVisible(find.text('통계 ›'));
      await tester.tap(find.text('통계 ›'));
      await tester.pumpAndSettle();
      expect(find.text('월별 보냄 · 받음'), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byType(AppBottomNav), matching: find.text('홈')));
      await tester.pumpAndSettle();
      expect(find.text('기록이 생기면 여기에 보여요'), findsNothing); // 추가 AC: 빈 그래프에 문구 없음
    });

    testWidgets('접은 상태는 저장되어 앱을 다시 켜도 그대로, 기본은 모두 펼침', (tester) async {
      await pump(tester, const HomeScreen());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefKeys.homeCollapsed('home_schedules')), isNull);
      await tester.tap(toggle(HomeSection.schedules));
      await tester.pumpAndSettle();
      await tester.ensureVisible(toggle(HomeSection.records));
      await tester.tap(toggle(HomeSection.records));
      await tester.pumpAndSettle();
      expect(prefs.getBool(PrefKeys.homeCollapsed('home_schedules')), isTrue);
      expect(prefs.getBool(PrefKeys.homeCollapsed('home_records')), isTrue);

      // 앱을 다시 켠 것과 같은 상황 (같은 저장소로 새로 그린다)
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(FakeRepository()),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('다가오는 일정이 없어요.'), findsNothing);
      expect(find.textContaining('첫 기록을 남겨보세요'), findsNothing);
      expect(find.text('기록이 생기면 여기에 보여요'), findsNothing); // 추가 AC: 빈 그래프에 문구 없음
    });

    testWidgets('결제 화면 혜택 4줄, 가져오기 · 엑셀 문구 없음', (tester) async {
      await pump(tester, const PaywallScreen());
      for (final t in [
        '사람을 제한 없이 등록해요',
        '(무료는 50명까지)',
        '내 행사 장부를 여러 개 만들어요',
        '(무료는 1개)',
        '관계별 · 연도별 상세 통계를 봐요',
        '한 번 결제로 평생 사용해요',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.textContaining('가져와'), findsNothing);
      expect(find.textContaining('엑셀'), findsNothing);
      expect(find.textContaining('CSV'), findsNothing);
    });

    // 추가 Z: 뒤로 가기 · 앱 종료
    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    Text tabLabel(WidgetTester tester, String t) => tester.widget<Text>(
        find.descendant(of: find.byType(AppBottomNav), matching: find.text(t)));

    testWidgets('홈이 아닌 탭에서 뒤로 가기: 홈 탭으로 (앱 종료 아님)', (tester) async {
      await pump(tester, const MainShell());
      for (final tab in ['사람', '행사', '통계']) {
        await tester.tap(find.descendant(
            of: find.byType(AppBottomNav), matching: find.text(tab)));
        await tester.pumpAndSettle();
        await back(tester);
        expect(find.text('앱을 종료할까요?'), findsNothing, reason: tab);
        expect(tabLabel(tester, '홈').style!.color, AppColors.primary,
            reason: tab);
        expect(find.text('보낸 마음'), findsOneWidget, reason: tab);
      }
    });

    testWidgets('홈에서 뒤로 가기: 앱을 종료할까요? [취소]면 그대로, [종료]면 종료',
        (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await pump(tester, const MainShell());
      await back(tester);
      expect(find.text('앱을 종료할까요?'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(find.text('앱을 종료할까요?'), findsNothing);
      expect(calls, isNot(contains('SystemNavigator.pop')));

      // 팝업에서 다시 뒤로 가기도 팝업만 닫는다
      await back(tester);
      await back(tester);
      expect(find.text('앱을 종료할까요?'), findsNothing);
      expect(find.text('보낸 마음'), findsOneWidget);
      expect(calls, isNot(contains('SystemNavigator.pop')));

      await back(tester);
      await tester.tap(find.text('종료'));
      await tester.pumpAndSettle();
      expect(calls, contains('SystemNavigator.pop'));
    });

    testWidgets('기록하기 메뉴가 열려 있으면 뒤로 가기는 메뉴만 닫는다', (tester) async {
      await pump(tester, const MainShell());
      await tester.tap(find.byTooltip('기록하기'));
      await tester.pumpAndSettle();
      expect(find.text('보냈어요'), findsOneWidget);
      await back(tester);
      expect(find.text('보냈어요'), findsNothing);
      expect(find.text('앱을 종료할까요?'), findsNothing);
    });

    testWidgets('사람 추가: 적은 내용이 있으면 작성 중 확인, [계속 작성]이면 그대로, 비었으면 바로 닫힘',
        (tester) async {
      await pump(tester, const MainShell());
      await tester.tap(find.descendant(
          of: find.byType(AppBottomNav), matching: find.text('사람')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ 추가'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonFormSheet), findsOneWidget);

      // 아무것도 안 적었으면 바로 닫힘
      await back(tester);
      expect(find.byType(PersonFormSheet), findsNothing);
      expect(find.text('작성 중인 내용이 있어요'), findsNothing);

      await tester.tap(find.text('+ 추가'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(of: find.byType(PersonFormSheet), matching: find.byType(TextField)).first,
          '김철수');
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.text('작성 중인 내용이 있어요'), findsOneWidget);
      await tester.tap(find.text('계속 작성'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonFormSheet), findsOneWidget);
      expect(find.text('김철수'), findsOneWidget);

      await back(tester);
      await tester.tap(find.text('나가기'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonFormSheet), findsNothing);
      expect(find.text('+ 추가'), findsOneWidget); // 사람 탭 그대로
    });

    testWidgets('일정 추가: 왼쪽 위 ←도 작성 중 확인을 거친다', (tester) async {
      await pump(
          tester,
          Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => const EventFormScreen())),
                      child: const Text('열기')))));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('열기'), findsOneWidget); // 빈 화면은 바로 나감

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '김철수');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('작성 중인 내용이 있어요'), findsOneWidget);
      await tester.tap(find.text('나가기'));
      await tester.pumpAndSettle();
      expect(find.text('열기'), findsOneWidget);
    });

    testWidgets('첫 실행 가이드: 뒤로 가기는 이전 장, 첫 장이면 그대로', (tester) async {
      await pump(tester, const OnboardingScreen());
      await back(tester);
      expect(find.text('주고받은 마음, 잊지 않게'), findsOneWidget);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('연필 버튼 하나면 돼요'), findsOneWidget);
      await back(tester);
      expect(find.text('주고받은 마음, 잊지 않게'), findsOneWidget);
    });

    testWidgets('홈 백업 아이콘은 v1에서 숨김(kShowHomeBackup = false)', (tester) async {
      expect(kShowHomeBackup, isFalse);
      await pump(tester, const HomeScreen());
      expect(find.text('백업'), findsNothing);
      expect(find.byType(BackupStatusButton), findsNothing);
    });

    testWidgets('kShowHomeBackup = true면: 기록이 있는데 백업이 없으면 백업 아이콘에 주황 점, 누르면 백업 안내',
        (tester) async {
      final repo = FakeRepository()
        ..inserted.addAll(List.generate(
            20,
            (_) => GiftRecord(
                personId: 1,
                direction: '보냄',
                amount: 1000,
                date: DateTime(2026))));
      await pump(tester, const HomeScreen(showBackup: true), repository: repo);
      expect(find.text('백업해 두면 폰을 바꿔도 기록이 안전해요'), findsNothing);
      expect(find.text('백업'), findsOneWidget);
      expect(find.byKey(const ValueKey('backup_due_dot')), findsOneWidget);
      await tester.tap(find.text('백업'));
      await tester.pumpAndSettle();
      expect(find.text('백업 안내'), findsOneWidget);
      expect(find.text('아직 백업이 없어요'), findsOneWidget);
      expect(find.text('지금 백업 파일 만들기'), findsOneWidget);
      expect(find.text('자동 백업 설정'), findsOneWidget);
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      expect(find.text('백업 안내'), findsNothing);
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

    testWidgets('일정 추가: 무료 50명이 차면 결제 화면이 뜨고, 닫으면 저장하지 않는다',
        (tester) async {
      final repo = FakeRepository()..people = 50;
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

  // 추가 Q: 받은 돈 적기로 합친 뒤 예전 입구 이름이 화면에 남지 않는다
  test('코드에 행사장 접수 · 받은 명단 직접 입력 같은 예전 문구가 없다', () {
    const old = [
      '행사장 접수',
      '받은 명단 직접 입력',
      '접수 장부',
      '접수 시작',
      '접수 마치기',
      '내 장부로 옮기기',
      '접수 결과',
    ];
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final w in old) {
          if (lines[i].contains(w)) hits.add('${f.path}:${i + 1} $w');
        }
      }
    }
    expect(hits, isEmpty);
  });

  // 추가 AC: '받은 돈 적기' → '행사 장부 작성'. 화면에 보이는 문구(주석 제외)에 예전 이름이 없다
  test('화면 문구에 받은 돈 적기 · 이어서 받기가 없다', () {
    const old = ['받은 돈 적기', '이어서 받기', '받은 돈을 적어요'];
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        for (final w in old) {
          if (RegExp("['\"][^'\"]*$w").hasMatch(line)) {
            hits.add('${f.path}:${i + 1} $w');
          }
        }
      }
    }
    expect(hits, isEmpty);
  });

  // 앱을 켤 때 알림 권한 확인. 권한이 없고 허용하지 않으면 행사 알림을 쓸 수 없다.
  group('알림 권한', () {
    var enabled = false;
    var requests = 0;

    setUp(() {
      enabled = false;
      requests = 0;
      NotificationService.debugAreEnabled = () async => enabled;
      NotificationService.debugRequest = () async {
        requests++;
        // 허용 창이 떠 있는 것처럼 잠깐 기다린다
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return enabled;
      };
    });
    tearDown(() {
      NotificationService.debugAreEnabled = null;
      NotificationService.debugRequest = null;
    });

    Future<void> pumpApp(WidgetTester tester, Widget home,
        {FakeRepository? repo}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'flutter.${PrefKeys.restorePromptDone}': true,
        'flutter.coach_seen_home': true,
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(repo ?? FakeRepository()),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: home),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('권한이 있으면 아무것도 묻지 않고 그냥 진행한다', (tester) async {
      enabled = true;
      await pumpApp(tester, const MainShell());
      expect(find.text('알림을 허용해 주세요'), findsNothing);
      expect(requests, 0);
    });

    testWidgets('권한이 없으면 앱을 켤 때 묻고, 허용하면 그냥 진행한다', (tester) async {
      await pumpApp(tester, const MainShell());
      expect(find.text('알림을 허용해 주세요'), findsOneWidget);
      enabled = true; // 허용 창에서 '허용'
      await tester.tap(find.text('허용하기'));
      await tester.pump(const Duration(seconds: 1)); // 허용 창이 닫힐 때까지
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('알림을 허용해 주세요'), findsNothing);
      expect(find.text('알림을 허용하지 않아 행사 알림은 쓸 수 없어요.'), findsNothing);
    });

    testWidgets('허용하지 않아도 스낵바 없음, 일정 알림 칩은 그대로 쓸 수 있다', (tester) async {
      await pumpApp(tester, const MainShell());
      await tester.tap(find.text('허용 안 함'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(find.text('알림을 허용하지 않아 행사 알림은 쓸 수 없어요.'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      // 일정이 없으면 '알림이 꺼져 있어요' 줄도 없다
      expect(find.text('알림이 꺼져 있어요'), findsNothing);

      // 추가 AC: 일정 화면은 스위치 대신 칩. 권한이 없어도 막지 않는다(기본 '1일 전 오전 9시')
      await pumpApp(tester, const EventFormScreen());
      expect(find.byType(SwitchListTile), findsNothing);
      for (final t in ['없음', '2일 전', '1일 전', '당일']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '1일 전')).selected,
          isTrue);
      expect(find.text('오전 9시'), findsOneWidget);
      // 날짜 기본값이 오늘이라 1일 전 9시는 이미 지났다
      expect(find.text('이미 지난 시간이라 알림이 오지 않아요'), findsOneWidget);
    });

    testWidgets('홈: 일정이 있고 알림이 꺼져 있으면 일정 아래 \'알림이 꺼져 있어요 · 켜기\', 켜면 사라진다',
        (tester) async {
      final repo = FakeRepository()
        ..upcoming = [
          Event(id: 7, type: '결혼', title: '철수 결혼식',
              date: DateTime.now().add(const Duration(days: 3)), isMine: false),
        ];
      await pumpApp(tester, const MainShell(), repo: repo);
      await tester.tap(find.text('허용 안 함'));
      await tester.pumpAndSettle();
      expect(find.text('알림이 꺼져 있어요'), findsOneWidget);
      // 일정 바로 아래
      expect(tester.getTopLeft(find.text('알림이 꺼져 있어요')).dy,
          greaterThan(tester.getTopLeft(find.text('철수 결혼식')).dy));
      enabled = true;
      await tester.tap(find.text('켜기'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('알림이 꺼져 있어요'), findsNothing);
    });

    testWidgets('설정: 알림 줄에 켜짐 / 꺼짐과 [설정 열기]', (tester) async {
      await pumpApp(tester, const SettingsScreen());
      await tester.scrollUntilVisible(find.text('설정 열기'), 200);
      expect(find.textContaining('꺼짐'), findsOneWidget);
      enabled = true;
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, const SettingsScreen());
      await tester.scrollUntilVisible(find.text('설정 열기'), 200);
      expect(find.textContaining('켜짐'), findsOneWidget);
      // Google 자동 백업 줄이 빠져 목록이 짧아지면서 아래 테스트 메뉴(DB 조회)까지 그려진다.
      // 그 조회의 대기 타이머가 끝나도록 시간을 흘려보낸다.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('일정 알림: [없음]이 아닌 값을 고르면 권한 창, 더 띄울 수 없으면 [설정 열기] 안내, 저장은 된다',
        (tester) async {
      final repo = FakeRepository();
      await pumpApp(tester, const EventFormScreen(), repo: repo);
      await tester.enterText(find.byType(TextField).first, '임원택');
      await tester.pumpAndSettle();
      // [없음]이면 시간 줄이 흐려지고 확인 문구가 없다
      await tester.tap(find.text('없음'));
      await tester.pumpAndSettle();
      expect(find.textContaining('쯤 알려드려요'), findsNothing);
      expect(requests, 0);
      // 아직 허용 창을 띄울 수 있으면 바로 허용 창 (거절해도 고른 값은 그대로)
      await tester.tap(find.text('2일 전'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(requests, 1);
      // 테스트 시계로는 허용 창이 '바로 거절'로 보일 수 있어, 안내가 떴으면 닫는다
      if (find.text('나중에').evaluate().isNotEmpty) {
        await tester.tap(find.text('나중에'));
        await tester.pumpAndSettle();
      }
      expect(
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '2일 전')).selected,
          isTrue);
      // 두 번 거절한 상태면 허용 창 대신 안내
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(PrefKeys.notifDeniedCount, 2);
      await tester.tap(find.text('당일'));
      await tester.pumpAndSettle();
      expect(find.text('알림이 꺼져 있어 이 일정 알림을 받을 수 없어요'), findsOneWidget);
      expect(find.text('설정 열기'), findsOneWidget);
      await tester.tap(find.text('나중에'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      // 시간은 1시간 단위로 고른다
      await tester.ensureVisible(find.text('시간'));
      await tester.tap(find.text('시간'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('오후 3시'));
      await tester.pumpAndSettle();
      expect(find.text('오후 3시'), findsOneWidget);
      await tester.ensureVisible(find.text('저장'));
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      final saved = repo.insertedEvents.single;
      expect(saved.reminderDays, 0);
      expect(saved.reminderHour, 15);
    });

    testWidgets('홈: 알림을 켜 둔 일정이 없으면 권한이 꺼져 있어도 \'알림이 꺼져 있어요\' 줄이 없다',
        (tester) async {
      final repo = FakeRepository()
        ..upcoming = [
          Event(id: 7, type: '결혼', title: '철수 결혼식',
              date: DateTime.now().add(const Duration(days: 3)),
              isMine: false, reminderDays: null),
        ];
      await pumpApp(tester, const MainShell(), repo: repo);
      await tester.tap(find.text('허용 안 함'));
      await tester.pumpAndSettle();
      expect(find.text('철수 결혼식'), findsOneWidget);
      expect(find.text('알림이 꺼져 있어요'), findsNothing);
    });
  });

  test('추가 AD: D±n은 날짜만 비교 (지난 날 D+n, 오늘 D-day, 앞으로 D-n)', () {
    final now = DateTime(2026, 11, 24, 23, 59);
    expect(dDayLabel(DateTime(2026, 11, 14), now: now), 'D+10');
    expect(dDayLabel(DateTime(2026, 11, 24, 0, 1), now: now), 'D-day');
    expect(dDayLabel(DateTime(2026, 11, 25), now: now), 'D-1');
    expect(dDayLabel(DateTime(2026, 12, 4), now: now), 'D-10');
  });

  test('추가 AC: 알림 문구 · 시간 표시', () {
    expect(hourLabel(7), '오전 7시');
    expect(hourLabel(12), '낮 12시');
    expect(hourLabel(18), '오후 6시');
    expect(hourLabel(0), '밤 12시');
    final e = Event(type: '결혼', title: '임원택 결혼식', date: DateTime(2026, 12, 5),
        isMine: false, place: '더채플');
    expect(e.reminderAt, DateTime(2026, 12, 4, 9));
    expect(NotificationService.reminderTitle(e), '내일 임원택 결혼식이에요');
    expect(NotificationService.reminderBody(e), '2026년 12월 5일 (토) · 더채플');
    final two = Event(type: '결혼', title: '임원택 결혼식', date: DateTime(2026, 12, 5),
        isMine: false, reminderDays: 2, reminderHour: 18);
    expect(NotificationService.reminderTitle(two), '모레 임원택 결혼식이에요');
    expect(two.reminderAt, DateTime(2026, 12, 3, 18));
    final same = Event(type: '결혼', title: 'A 결혼식', date: DateTime(2026, 12, 5),
        isMine: false, reminderDays: 0);
    expect(NotificationService.reminderTitle(same), '오늘 A 결혼식이에요');
    expect(reminderLabel(two), '2일 전 오후 6시');
  });

  group('사람 탭 인원 제목 줄 (추가 U)', () {
    Future<void> pumpPeople(WidgetTester tester, {required bool pro}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'flutter.${PrefKeys.notifPermissionAsked}': true,
        'flutter.${PrefKeys.devProOverride}': pro,
        'flutter.coach_seen_people': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = FakeRepository()
        ..summaries = [
          PersonSummary(
              person: Person(id: 1, name: '김철수', relation: '가족', createdAt: DateTime(2026)),
              sentTotal: 0,
              receivedTotal: 0),
        ];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const PeopleScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('무료: 헤더는 사람 + ? + 설정만, \'전체 1명 · 무료 50명까지\' + 막대', (tester) async {
      await pumpPeople(tester, pro: false);
      expect(find.text('1 / 50명'), findsNothing);
      expect(find.text('사람 추가'), findsNothing);
      expect(find.text('전체 1명'), findsOneWidget);
      expect(find.text('· 무료 50명까지'), findsOneWidget);
      expect(find.text('+ 추가'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(bar.value, closeTo(1 / 50, 1e-9));

      // 칩을 고르면 '가족 1명', 무료 표시 · 막대는 '전체'일 때만
      await tester.tap(find.widgetWithText(ChoiceChip, '가족'));
      await tester.pumpAndSettle();
      expect(find.text('가족 1명'), findsOneWidget);
      expect(find.text('· 무료 50명까지'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, '전체'));
      await tester.enterText(find.byType(TextField), '없는이름');
      await tester.pumpAndSettle();
      expect(find.text('검색 결과 0명'), findsOneWidget);
    });

    testWidgets('프로: \'전체 1명\'만, 막대 없음', (tester) async {
      await pumpPeople(tester, pro: true);
      expect(find.text('전체 1명'), findsOneWidget);
      expect(find.text('· 무료 50명까지'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });
}
