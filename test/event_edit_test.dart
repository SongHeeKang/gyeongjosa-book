// 추가 AA: 행사 수정 · 삭제, 홈 목록 높이 제한
import 'dart:io';

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
import 'package:gyeongjosa/screens/reception_form_screen.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:gyeongjosa/widgets/capped_scroll_list.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Reception _reception() => Reception(
      id: 'r1',
      title: '누나 결혼식',
      eventType: '결혼',
      date: DateTime(2026, 12, 26),
      sides: const ['신랑측', '신부측'],
      operatorName: '송희강',
      startedAt: DateTime(2026, 12, 26, 9),
      mealTicketEnabled: true,
      methodEnabled: true,
    );

Event _myEvent() => Event(
      id: 1,
      type: '결혼',
      title: '우리 결혼식',
      date: DateTime(2026, 10, 3),
      isMine: true,
      receiveSides: const ['신랑측', '신부측'],
      mealTicketEnabled: true,
      methodEnabled: false,
    );

class _FakeRepository extends Repository {
  _FakeRepository() : super(DatabaseHelper.forTest('unused.db'));
  ({Reception reception, Map<String, String> renames})? savedReception;
  ({Event event, Map<String, String> renames})? savedEvent;
  final deletedReceptions = <String>[];

  @override
  Future<void> updateReceptionInfo(
          Reception reception, Map<String, String> renames) async =>
      savedReception = (reception: reception, renames: renames);
  @override
  Future<void> updateMyEventInfo(Event event, Map<String, String> renames) async =>
      savedEvent = (event: event, renames: renames);
  @override
  Future<void> deleteReception(String id) async => deletedReceptions.add(id);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUpAll(() => initializeDateFormatting('ko_KR'));

  group('행사 수정 화면', () {
    Future<_FakeRepository> open(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(1080, 4400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(
          {'flutter.${PrefKeys.notifPermissionAsked}': true});
      final prefs = await SharedPreferences.getInstance();
      final repo = _FakeRepository();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => screen)),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      return repo;
    }

    Widget otherEdit() => ReceptionFormScreen.edit(
          editReception: _reception(),
          sideCounts: const {'신랑측': 3, '신부측': 0},
          guestCount: 3,
        );

    testWidgets('다른 사람 행사: 지금 값이 채워지고, 누구 행사예요?는 바꿀 수 없다',
        (tester) async {
      await open(tester, otherEdit());
      expect(find.text('행사 수정'), findsOneWidget);
      expect(find.text('누나 결혼식'), findsOneWidget);
      expect(find.text('송희강'), findsOneWidget);
      expect(find.text('2026년 12월 26일 (토)'), findsOneWidget);
      expect(find.text('내 행사로 바꾸려면 행사 상세의 [내 행사로 바꾸기]'), findsOneWidget);
      final mine = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '내 행사'));
      expect(mine.onPressed, isNull);
      expect(find.text('저장'), findsOneWidget);
      expect(find.text('받기 시작'), findsNothing);
      expect(find.text('행사 삭제'), findsOneWidget);
    });

    testWidgets('손님이 있는 구분은 지울 수 없고, 이름을 바꾸면 기존 손님도 같이', (tester) async {
      final repo = await open(tester, otherEdit());
      expect(find.text('이 구분으로 적은 3명이 있어요'), findsOneWidget);
      final buttons = tester
          .widgetList<IconButton>(find.ancestor(
              of: find.byTooltip('구분 지우기'),
              matching: find.byType(IconButton)))
          .toList();
      expect(buttons[0].onPressed, isNull); // 신랑측: 손님 3명
      expect(buttons[1].onPressed, isNotNull); // 신부측: 손님 없음

      await tester.enterText(find.widgetWithText(TextField, '신랑측'), '신랑 측');
      await tester.enterText(find.widgetWithText(TextField, '누나 결혼식'), '언니 결혼식');
      await tester.enterText(find.widgetWithText(TextField, '송희강'), '김희강');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      final saved = repo.savedReception!;
      expect(saved.renames, {'신랑측': '신랑 측'});
      expect(saved.reception.sides, ['신랑 측', '신부측']);
      expect(saved.reception.title, '언니 결혼식');
      expect(saved.reception.operatorName, '김희강');
      expect(saved.reception.mealTicketEnabled, isTrue);
      expect(find.text('행사 수정'), findsNothing); // 저장 후 닫힘
    });

    testWidgets('바꾼 뒤 뒤로 가기: 작성 중 확인', (tester) async {
      await open(tester, otherEdit());
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('열기'), findsOneWidget); // 안 바꿨으면 바로 나감

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('식권 기록 안 함'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('작성 중인 내용이 있어요'), findsOneWidget);
    });

    testWidgets('행사 삭제는 두 번 확인한 뒤 지운다', (tester) async {
      final repo = await open(tester, otherEdit());
      await tester.ensureVisible(find.text('행사 삭제'));
      await tester.tap(find.text('행사 삭제'));
      await tester.pumpAndSettle();
      expect(find.text('이 행사와 손님 3명을 지울까요?'), findsOneWidget);
      await tester.tap(find.text('지우기'));
      await tester.pumpAndSettle();
      expect(find.text('정말 지울까요?'), findsOneWidget);
      expect(repo.deletedReceptions, isEmpty);
      await tester.tap(find.text('지우기'));
      await tester.pumpAndSettle();
      expect(repo.deletedReceptions, ['r1']);
    });

    testWidgets('내 행사: 장소 · 메모도 고치고, 식권을 꺼도 저장(기존 값은 저장소에서 그대로)',
        (tester) async {
      final repo = await open(
          tester,
          ReceptionFormScreen.edit(
              editEvent: _myEvent(),
              sideCounts: const {'신랑측': 1},
              guestCount: 1));
      expect(find.text('장소 (선택)'), findsOneWidget);
      expect(find.text('받는 사람 이름'), findsNothing);
      await tester.tap(find.text('식권 기록 안 함'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('저장'));
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(repo.savedEvent!.event.mealTicketEnabled, isFalse);
      expect(repo.savedEvent!.event.id, 1);
      expect(repo.savedEvent!.renames, isEmpty);
    });
  });

  group('저장소: 행사 수정', () {
    late Directory dir;
    late DatabaseHelper helper;
    late Repository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('gyeongjosa_edit');
      helper = DatabaseHelper.forTest(p.join(dir.path, 'test.db'));
      repo = Repository(helper);
    });

    tearDown(() async {
      await helper.close();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('다른 사람 행사: 구분 이름을 바꾸면 손님 구분도, 식권 값은 그대로', () async {
      await repo.insertReception(_reception());
      await repo.insertReceptionEntry(ReceptionEntry(
          id: 'a',
          receptionId: 'r1',
          name: '김철수',
          amount: 50000,
          side: '신랑측',
          mealTickets: 2,
          createdAt: DateTime(2026, 12, 26, 11)));
      final r = _reception();
      await repo.updateReceptionInfo(
        Reception(
          id: r.id,
          title: '언니 결혼식',
          eventType: r.eventType,
          date: DateTime(2026, 12, 27),
          sides: const ['신랑 측', '신부측'],
          operatorName: '김희강',
          startedAt: r.startedAt,
          mealTicketEnabled: false,
          methodEnabled: r.methodEnabled,
        ),
        {'신랑측': '신랑 측'},
      );
      final back = (await repo.getReceptionPackage('r1'))!;
      expect(back.reception.title, '언니 결혼식');
      expect(back.reception.operatorName, '김희강');
      expect(back.reception.date, DateTime(2026, 12, 27));
      expect(back.entries.single.side, '신랑 측');
      expect(back.entries.single.mealTickets, 2);
      expect(back.showsMealTickets, isTrue); // 꺼도 이미 적은 식권은 보인다
    });

    test('내 행사: 날짜 · 이름을 바꾸면 받음 기록의 날짜 · 행사 이름도, 보냄 기록은 그대로',
        () async {
      final personId = await repo.insertPerson(
          Person(name: '김철수', createdAt: DateTime(2026)));
      final eventId = await repo.insertEvent(_myEvent().withReceiveSettings(
          sides: const ['신랑측'],
          mealTicketEnabled: false,
          defaultMealTickets: 1,
          methodEnabled: false));
      await repo.insertRecord(GiftRecord(
          personId: personId,
          eventId: eventId,
          direction: '받음',
          amount: 50000,
          date: DateTime(2026, 10, 3),
          side: '신랑측'));
      await repo.insertRecord(GiftRecord(
          personId: personId,
          direction: '보냄',
          amount: 30000,
          date: DateTime(2026, 5, 1)));
      final e = (await repo.getEvent(eventId))!;
      await repo.updateMyEventInfo(
        Event(
          id: e.id,
          type: e.type,
          title: '우리 결혼식(본식)',
          date: DateTime(2026, 10, 4),
          isMine: true,
          receiveSides: const ['신랑 측'],
          mealTicketEnabled: false,
          methodEnabled: false,
        ),
        {'신랑측': '신랑 측'},
      );
      final records = await repo.recordsForPerson(personId);
      final received = records.firstWhere((r) => r.direction == '받음');
      expect(received.date, DateTime(2026, 10, 4));
      expect(received.eventTitle, '우리 결혼식(본식)');
      expect(received.side, '신랑 측');
      final sent = records.firstWhere((r) => r.direction == '보냄');
      expect(sent.date, DateTime(2026, 5, 1));
      expect((await repo.monthlyTotals(2026))[9].received, 50000);
    });

    test('내 행사를 지우면 0개가 되어 다시 만들 수 있고, 받음 기록은 남는다', () async {
      final personId = await repo.insertPerson(
          Person(name: '김철수', createdAt: DateTime(2026)));
      final eventId = await repo.insertEvent(_myEvent());
      await repo.insertRecord(GiftRecord(
          personId: personId,
          eventId: eventId,
          direction: '받음',
          amount: 50000,
          date: DateTime(2026, 10, 3)));
      expect(await repo.countMyEvents(), 1);
      await repo.deleteEvent(eventId);
      expect(await repo.countMyEvents(), 0);
      expect(await repo.countRecords(), 1);
    });
  });

  group('홈 목록 높이', () {
    Future<void> pumpList(WidgetTester tester, int count) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              const SizedBox(height: 300, child: Text('위')),
              CappedScrollList(
                itemCount: count,
                itemBuilder: (_, i) =>
                    SizedBox(height: 60, child: Text('항목 $i')),
              ),
              const SizedBox(height: 900, child: Text('아래')),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('적으면 내용만큼(2줄 = 120)', (tester) async {
      await pumpList(tester, 2);
      expect(tester.getSize(find.byType(CappedScrollList)).height, 120);
    });

    testWidgets('많으면 4.5줄(270)까지만, 보이는 것만 그리고 안에서 스크롤해 끝까지', (tester) async {
      await pumpList(tester, 300);
      expect(tester.getSize(find.byType(CappedScrollList)).height, 270);
      expect(find.text('항목 299'), findsNothing);
      expect(find.text('항목 100'), findsNothing); // 보이지 않는 것은 그리지 않음
      final inner = find.descendant(
          of: find.byType(CappedScrollList), matching: find.byType(Scrollable));
      final controller = tester.widget<Scrollable>(inner).controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('항목 299'), findsOneWidget);
    });

    testWidgets('안쪽이 끝에 닿으면 화면 전체가 이어서 스크롤', (tester) async {
      await pumpList(tester, 6);
      final outer = tester
          .widget<Scrollable>(find.byType(Scrollable).first)
          .controller!;
      expect(outer.offset, 0);
      // 안쪽 목록을 위로 크게 끌면, 끝에 닿은 뒤 남은 만큼 바깥이 움직인다
      await tester.drag(find.text('항목 2'), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(outer.offset, greaterThan(0));
    });
  });
}
