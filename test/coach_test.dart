import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/providers.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/screens/help_screen.dart';
import 'package:gyeongjosa/screens/main_shell.dart';
import 'package:gyeongjosa/screens/reception_screen.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:gyeongjosa/widgets/app_bottom_nav.dart';
import 'package:gyeongjosa/widgets/coach_mark.dart';
import 'package:gyeongjosa/widgets/screen_coach.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 화면만 확인하는 저장소. 데이터가 없는 상태.
class _FakeRepository extends Repository {
  _FakeRepository() : super(DatabaseHelper.forTest('unused.db'));

  final reception = Reception(
    id: 'r1',
    title: '홍길동 결혼식',
    eventType: '결혼',
    date: DateTime(2026, 11, 1),
    sides: const ['신랑측', '신부측'],
    operatorName: '김민수',
    startedAt: DateTime(2026, 11, 1, 9),
  );
  final entries = <ReceptionEntry>[];

  @override
  Future<ReceptionPackage?> getReceptionPackage(String id) async =>
      ReceptionPackage(reception, entries.reversed.toList());
  @override
  Future<void> insertReceptionEntry(ReceptionEntry entry) async =>
      entries.add(entry);
  @override
  Future<({int sent, int received, int sentCount, int receivedCount})> yearTotals(
          int year) async =>
      (sent: 0, received: 0, sentCount: 0, receivedCount: 0);
  @override
  Future<List<Never>> upcomingSchedules({int? limit}) async => const [];
  @override
  Future<List<Never>> pendingAmountEvents({int? limit}) async => const [];
  @override
  Future<int> countSchedules() async => 0;
  @override
  Future<List<Never>> recentRecords(int limit) async => const [];
  @override
  Future<int> countRecords() async => 0;
  @override
  Future<List<Never>> peopleSummaries() async => const [];
  @override
  Future<List<Never>> allPeople() async => const [];
  @override
  Future<List<Never>> eventSummaries() async => const [];
  @override
  Future<List<Never>> receptionSummaries() async => const [];
  @override
  Future<List<int>> recordYears() async => [DateTime.now().year];
}

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  group('문구 자리', () {
    const screen = Size(411, 900);
    List<Rect> layout(List<Rect> holes, {double bottom = 800}) =>
        layoutCoachLabels(
          screen: screen,
          top: 30,
          bottom: bottom,
          holes: holes,
          sizes: List.filled(holes.length, const Size(240, 44)),
        );

    void expectClean(List<Rect> labels, List<Rect> holes,
        {double bottom = 800}) {
      for (var i = 0; i < labels.length; i++) {
        final l = labels[i];
        expect(l.left, greaterThanOrEqualTo(0));
        expect(l.right, lessThanOrEqualTo(screen.width));
        expect(l.top, greaterThanOrEqualTo(30));
        expect(l.bottom, lessThanOrEqualTo(bottom));
        for (final h in holes) {
          expect(l.overlaps(h), isFalse, reason: '$l / $h');
        }
        for (var j = i + 1; j < labels.length; j++) {
          expect(l.overlaps(labels[j]), isFalse);
        }
      }
    }

    test('오른쪽 위, 아래, 가운데 대상이 함께 있어도 겹치지 않는다', () {
      const holes = [
        Rect.fromLTWH(300, 760, 90, 56), // 기록하기
        Rect.fromLTWH(24, 300, 363, 120), // 얼마 내셨어요
        Rect.fromLTWH(320, 40, 48, 48), // ?
      ];
      expectClean(layout(holes), holes);
    });

    test('세로로 붙은 카드 4개도 문구가 위쪽에 차례로 쌓인다', () {
      const holes = [
        Rect.fromLTWH(107, 500, 280, 60),
        Rect.fromLTWH(107, 570, 280, 60),
        Rect.fromLTWH(107, 640, 280, 60),
        Rect.fromLTWH(107, 710, 280, 60),
      ];
      final labels = layout(holes);
      expectClean(labels, holes);
    });

    test('대상 사이가 좁으면 멀리 밀리지 않고 그 사이에 들어간다', () {
      const holes = [
        Rect.fromLTWH(20, 100, 370, 60),
        Rect.fromLTWH(0, 216, 411, 70),
      ];
      final labels = layoutCoachLabels(
        screen: screen,
        top: 30,
        bottom: 800,
        holes: holes,
        sizes: const [Size(120, 24), Size(240, 44)],
      );
      expect(labels[0].top, greaterThanOrEqualTo(160));
      expect(labels[0].bottom, lessThanOrEqualTo(216));
    });

    test('붙어 있는 버튼 3개는 첫째 위, 셋째 아래, 가운데는 남은 자리에 놓고 겹치지 않는다', () {
      const holes = [
        Rect.fromLTWH(24, 250, 363, 56),
        Rect.fromLTWH(24, 310, 363, 56),
        Rect.fromLTWH(24, 370, 363, 56),
      ];
      final labels = layout(holes);
      expectClean(labels, holes);
      expect(labels[0].bottom, lessThanOrEqualTo(holes[0].top));
      expect(labels[2].top, greaterThanOrEqualTo(holes[2].bottom));
      expect(labels[1].top, greaterThanOrEqualTo(labels[2].bottom));
    });

    test('곧은 화살표는 짧고, 다른 문구나 자리를 지나가지 않는다', () {
      const holes = [
        Rect.fromLTWH(80, 300, 300, 60), // 묶음 하나, 첫째
        Rect.fromLTWH(320, 40, 48, 48),
        Rect.fromLTWH(300, 760, 70, 70),
      ];
      final labels = layout(holes);
      for (var i = 0; i < holes.length; i++) {
        final (start, end) = coachArrowEnds(labels[i], holes[i]);
        expect((end - start).distance, lessThanOrEqualTo(80));
        for (var j = 0; j < holes.length; j++) {
          if (j == i) continue;
          for (var t = 0.0; t <= 1; t += 0.1) {
            final p = Offset.lerp(start, end, t)!;
            expect(holes[j].contains(p), isFalse);
            expect(labels[j].contains(p), isFalse);
          }
        }
      }
    });

    test('피해야 할 자리에는 문구를 놓지 않는다', () {
      const holes = [Rect.fromLTWH(24, 700, 363, 100)];
      const blocked = Rect.fromLTWH(60, 560, 280, 130);
      final label = layoutCoachLabels(
        screen: screen,
        top: 30,
        bottom: 860,
        holes: holes,
        sizes: const [Size(240, 44)],
        avoid: const [blocked],
      ).single;
      expect(label.overlaps(blocked), isFalse);
    });

    test('큰 대상 위아래에 자리가 없어도 화면 안에 놓는다', () {
      const holes = [Rect.fromLTWH(0, 30, 411, 770)];
      final label = layout(holes).single;
      expect(label.left, greaterThanOrEqualTo(0));
      expect(label.top, greaterThanOrEqualTo(30));
    });
  });

  Future<(SharedPreferences, _FakeRepository)> pump(
    WidgetTester tester,
    Widget home, {
    bool ready = true,
    Map<String, Object> prefsValues = const {},
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'flutter.${PrefKeys.notifPermissionAsked}': true,
      if (ready) 'flutter.${PrefKeys.restorePromptDone}': true,
      for (final e in prefsValues.entries) 'flutter.${e.key}': e.value,
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = _FakeRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        repositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: home),
    ));
    await tester.pump();
    return (prefs, repo);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  const homeText = '모든 기록은 여기서 시작해요';

  group('자동 도움말', () {
    testWidgets('처음 들어가면 뜨고, 아무 데나 누르면 닫히며, 다시 뜨지 않는다', (tester) async {
      await pump(tester, const MainShell());
      await settle(tester);
      expect(find.text(homeText), findsOneWidget);
      expect(find.text('알겠어요'), findsOneWidget);
      expect(find.text('오른쪽 위 ? 버튼으로 다시 볼 수 있어요'), findsOneWidget);
      // 안내문이 버튼 위에, 둘 다 하단 탭보다 위에
      final hint = tester.getRect(find.text('오른쪽 위 ? 버튼으로 다시 볼 수 있어요'));
      final ok = tester.getRect(find.text('알겠어요'));
      final nav = tester.getRect(find.byType(AppBottomNav));
      expect(hint.bottom, lessThanOrEqualTo(ok.top));
      expect(ok.bottom + 8, lessThanOrEqualTo(nav.top));
      expect(find.byIcon(Icons.close), findsNothing);

      await tester.tapAt(const Offset(200, 500));
      await settle(tester);
      expect(find.text(homeText), findsNothing);

      // 다른 탭에 갔다 돌아와도 다시 뜨지 않는다
      await tester.tap(find.descendant(
          of: find.byType(AppBottomNav), matching: find.text('사람')));
      await settle(tester);
      expect(find.text('이름으로 찾아요'), findsOneWidget);
      await tester.tap(find.text('알겠어요'));
      await settle(tester);
      await tester.tap(find.descendant(
          of: find.byType(AppBottomNav), matching: find.text('홈')));
      await settle(tester);
      expect(find.text(homeText), findsNothing);
    });

    testWidgets('첫 실행 안내(이전 백업 묻기)가 끝나기 전에는 뜨지 않는다', (tester) async {
      await pump(tester, const MainShell(), ready: false);
      await settle(tester);
      expect(find.text(homeText), findsNothing);
    });

    testWidgets('? 버튼으로 언제든 다시 본다. 없는 자리는 건너뛴다', (tester) async {
      await pump(tester, const MainShell(), prefsValues: {
        'coach_seen_home': true,
      });
      await settle(tester);
      expect(find.text(homeText), findsNothing);
      await tester.tap(find.byTooltip('도움말').first);
      await settle(tester);
      expect(find.text(homeText), findsOneWidget);
      expect(find.text('이 도움말은 여기서 다시 볼 수 있어요'), findsOneWidget);
      // '얼마 내셨어요?'가 없는 상태
      expect(find.text('다녀온 행사는 금액만 누르면 기록돼요'), findsNothing);
    });

    testWidgets('처음부터 다시 보기를 누르면 다시 자동으로 뜬다', (tester) async {
      final (prefs, _) = await pump(tester, const HelpScreen(),
          prefsValues: {'coach_seen_home': true, 'coach_seen_stats': true});
      await settle(tester);
      expect(find.text('처음 4장 가이드'), findsOneWidget);
      expect(find.text('받은 명단 직접 입력'), findsOneWidget);
      await tester.tap(find.text('도움말 처음부터 다시 보기'));
      await tester.pump();
      expect(prefs.getBool('coach_seen_home'), isNull);
      expect(prefs.getBool('coach_seen_stats'), isNull);
      for (final s in CoachScreen.values) {
        expect(s.marks.length, inInclusiveRange(1, 3), reason: s.title);
      }
    });
  });

  group('행사장 접수 도움말', () {
    const text = '이름을 적고 금액을 누르면 바로 저장';
    testWidgets('첫 저장 전에 뜨고 최근 저장 자리까지 가리킨다', (tester) async {
      await pump(tester, const ReceptionScreen(receptionId: 'r1'));
      await settle(tester);
      expect(find.text(text), findsOneWidget);
      expect(find.text('방금 저장한 손님이 맨 위에'), findsOneWidget);
      expect(find.text('끝나면 혼주에게 보내요'), findsOneWidget);
      await tester.tap(find.text('알겠어요'));
      await settle(tester);
      final name = tester.widget<TextField>(find.byType(TextField).first);
      expect(name.focusNode!.hasFocus, isTrue);
    });

    testWidgets('이미 저장한 항목이 있으면 자동으로 뜨지 않고, ?로는 볼 수 있다', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(
          {'flutter.${PrefKeys.restorePromptDone}': true});
      final prefs = await SharedPreferences.getInstance();
      final repo = _FakeRepository()
        ..entries.add(ReceptionEntry(
          id: 'e1',
          receptionId: 'r1',
          name: '김철수',
          amount: 50000,
          side: '신랑측',
          createdAt: DateTime(2026, 11, 1, 9),
        ));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
            theme: buildAppTheme(),
            home: const ReceptionScreen(receptionId: 'r1')),
      ));
      await tester.pump();
      await settle(tester);
      expect(find.text(text), findsNothing);
      await tester.tap(find.byTooltip('도움말'));
      await settle(tester);
      expect(find.text(text), findsOneWidget);
    });
  });

  group('기록하기 메뉴', () {
    Future<void> open(WidgetTester tester) async {
      await pump(tester, const MainShell(), prefsValues: {
        'coach_seen_home': true,
        'coach_seen_recordMenu': true,
      });
      await settle(tester);
      await tester.tap(find.text('기록하기'));
      await tester.pumpAndSettle();
    }

    testWidgets('카드가 위에서부터 4개 쌓이고, 기록하기 대신 같은 자리에 X가 보인다', (tester) async {
      await pump(tester, const MainShell(),
          prefsValues: {'coach_seen_home': true, 'coach_seen_recordMenu': true});
      await settle(tester);
      final pill = tester.getRect(find.text('기록하기'));
      await tester.tap(find.text('기록하기'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final tops = [
        for (final t in ['보냈어요', '일정 추가', '받은 명단 직접 입력', '행사장 접수'])
          tester.getTopLeft(find.text(t)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(find.text('종이 장부·계좌이체를 옮겨 적어요'), findsOneWidget);

      expect(find.text('기록하기').hitTestable(), findsNothing);
      final close = find.bySemanticsLabel('닫기');
      expect(close, findsWidgets);
      final x = tester.getRect(find.byIcon(Icons.add).last);
      expect(x.center.dy, closeTo(pill.center.dy, 8));
    });

    testWidgets('배경을 누르면 닫히고 기록하기 버튼이 돌아온다', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(10, 200));
      await tester.pumpAndSettle();
      expect(find.text('보냈어요'), findsNothing);
      expect(find.text('기록하기').hitTestable(), findsOneWidget);
    });

    testWidgets('뒤로가기로도 닫힌다', (tester) async {
      await open(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('보냈어요'), findsNothing);
    });

    testWidgets('X를 누르면 닫힌다', (tester) async {
      await open(tester);
      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pumpAndSettle();
      expect(find.text('보냈어요'), findsNothing);
    });

    testWidgets('카드를 누르면 메뉴를 닫고 해당 화면으로 간다', (tester) async {
      await open(tester);
      await tester.tap(find.text('행사장 접수'));
      await tester.pumpAndSettle();
      expect(find.text('보냈어요'), findsNothing);
      expect(find.text('접수 시작'), findsOneWidget);
    });

    testWidgets('처음 열 때 카드를 가리키는 도움말이 뜬다', (tester) async {
      await pump(tester, const MainShell(),
          prefsValues: {'coach_seen_home': true});
      await settle(tester);
      await tester.tap(find.text('기록하기'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      // 카드마다 따로 설명하지 않고 하나로 묶는다
      expect(find.text('하고 싶은 일을 고르세요\n카드마다 무엇을 하는지 적혀 있어요'),
          findsOneWidget);
      expect(find.text('내가 낸 축의금·부의금'), findsNothing);
      expect(find.text('닫기'), findsOneWidget);
      final group = CoachScreen.recordMenu.marks.single.rect!;
      for (final card in ['보냈어요', '행사장 접수']) {
        expect(group.contains(tester.getCenter(find.text(card))), isTrue);
      }
      // 설명은 묶음 바로 위에 있다
      final label = tester.getRect(find.text(
          '하고 싶은 일을 고르세요\n카드마다 무엇을 하는지 적혀 있어요'));
      expect(label.bottom, lessThan(group.top));
      expect(group.top - label.bottom, lessThanOrEqualTo(80));

      await tester.tap(find.text('알겠어요'));
      await settle(tester);
      // 도움말을 닫아도 메뉴는 그대로
      expect(find.text('보냈어요'), findsOneWidget);
    });
  });
}
