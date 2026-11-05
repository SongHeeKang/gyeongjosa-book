import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/providers.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/event.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/screens/paywall_screen.dart';
import 'package:gyeongjosa/screens/reception_form_screen.dart';
import 'package:gyeongjosa/screens/reception_import_screen.dart';
import 'package:gyeongjosa/screens/reception_screen.dart';
import 'package:gyeongjosa/services/limits.dart';
import 'package:gyeongjosa/services/reception_import.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 화면 동작만 확인하는 메모리 저장소
class FakeRepository extends Repository {
  FakeRepository() : super(DatabaseHelper.forTest('unused.db'));

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
  Future<void> deleteReceptionEntry(String id) async =>
      entries.removeWhere((e) => e.id == id);
}

/// 가져오기 화면용: 사람이 한 명도 없는 상태에서 31명짜리 파일을 가져온다.
class ImportFakeRepository extends Repository {
  ImportFakeRepository() : super(DatabaseHelper.forTest('unused.db'));

  final package = ReceptionPackage(
    Reception(
      id: 'r1',
      title: '홍길동 결혼식',
      eventType: '결혼',
      date: DateTime(2026, 11, 1),
      sides: const ['신랑측'],
      operatorName: '김민수',
      startedAt: DateTime(2026, 11, 1),
    ),
    [
      for (var i = 0; i < 31; i++)
        ReceptionEntry(
          id: 'e$i',
          receptionId: 'r1',
          name: '손님$i',
          amount: 50000,
          side: '신랑측',
          createdAt: DateTime(2026, 11, 1).add(Duration(minutes: i)),
        ),
    ],
  );

  /// applyImport에 넘어온 사람 한도
  final appliedLimits = <int?>[];

  @override
  Future<List<EventSummary>> eventSummaries() async => const [];

  @override
  Future<int> countMyEvents() async => 0;

  @override
  Future<Event?> getEvent(int id) async => null;

  ImportPlan _plan(int? maxPeople) => buildImportPlan(
        entries: package.entries,
        importedIds: const {},
        peopleByName: const {},
        namesInEvent: const {},
        newPersonSlots: maxPeople,
      );

  @override
  Future<ImportPlan> planImport(ReceptionPackage package,
          {int? eventId, int? maxPeople}) async =>
      _plan(maxPeople);

  @override
  Future<({int eventId, ImportPlan plan})> applyImport(
    ReceptionPackage package, {
    int? eventId,
    Event? newEvent,
    int? maxPeople,
  }) async {
    appliedLimits.add(maxPeople);
    return (eventId: 1, plan: _plan(maxPeople));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  Future<FakeRepository> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeRepository();
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
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) =>
                          const ReceptionScreen(receptionId: 'r1'))),
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

  testWidgets('금액 버튼을 누르면 바로 저장되고 이름칸이 비워진다', (tester) async {
    final repo = await open(tester);

    await tester.enterText(find.byType(TextField).first, '김철수');
    await tester.tap(find.text('5만'));
    await tester.pumpAndSettle();

    expect(repo.entries.single.name, '김철수');
    expect(repo.entries.single.amount, 50000);
    expect(repo.entries.single.side, '신랑측');
    expect(repo.entries.single.mealTickets, 1);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(find.text('1명 · 50,000원'), findsOneWidget);
  });

  testWidgets('이름 없이 금액을 누르면 저장하지 않고 안내한다', (tester) async {
    final repo = await open(tester);

    await tester.tap(find.text('10만'));
    await tester.pumpAndSettle();

    expect(repo.entries, isEmpty);
    expect(find.text('이름을 먼저 입력해 주세요'), findsOneWidget);
  });

  testWidgets('같은 이름은 경고만 하고 저장은 막지 않는다', (tester) async {
    final repo = await open(tester);

    await tester.enterText(find.byType(TextField).first, '김철수');
    await tester.tap(find.text('5만'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '김철수');
    await tester.pumpAndSettle();
    expect(find.text('같은 이름이 있어요'), findsOneWidget);

    await tester.tap(find.text('15만'));
    await tester.pumpAndSettle();
    expect(repo.entries.length, 2);
    // 저장 뒤에도 '방금 저장' 줄에서 경고한다
    expect(find.text('같은 이름이 있어요'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('금액 버튼은 8개이고 눌러도 키보드 포커스가 이름칸에 남는다', (tester) async {
    final repo = await open(tester);
    for (final label in ['5만', '10만', '15만', '20만', '25만', '30만', '50만', '100만']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.enterText(find.byType(TextField).first, '박민수');
    await tester.tap(find.text('100만'));
    await tester.pumpAndSettle();
    expect(repo.entries.single.amount, 1000000);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('키보드가 열리면 현황은 한 줄, 전체 내역 대신 방금 저장 줄만', (tester) async {
    final repo = await open(tester);
    for (final name in ['김철수', '이영희']) {
      await tester.enterText(find.byType(TextField).first, name);
      await tester.tap(find.text('5만'));
      await tester.pumpAndSettle();
    }
    expect(repo.entries.length, 2);
    // 키보드 닫힘: 구분별 소계와 전체 내역이 보인다
    expect(find.textContaining('신랑측 2명'), findsOneWidget);
    expect(find.text('김철수'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('신랑측 2명'), findsNothing);
    expect(find.text('김철수'), findsNothing);
    expect(find.text('2명 · 100,000원'), findsOneWidget);
    expect(find.textContaining('이영희 · 5만 · '), findsOneWidget);
    expect(find.text('되돌리기'), findsOneWidget);
    // 금액 패드는 키보드 위에 그대로 있다
    expect(find.text('100만'), findsOneWidget);
  });

  testWidgets('전체 접수 내역은 저장 시각과 함께 끝까지 스크롤된다', (tester) async {
    final repo = await open(tester);
    for (var i = 0; i < 30; i++) {
      repo.entries.add(ReceptionEntry(
        id: 'e$i',
        receptionId: 'r1',
        name: '손님$i',
        amount: 50000,
        side: '신랑측',
        createdAt: DateTime(2026, 11, 1, 12, 34),
      ));
    }
    await tester.enterText(find.byType(TextField).first, '마지막손님');
    await tester.tap(find.text('5만'));
    await tester.pumpAndSettle();
    expect(find.textContaining('오후 12:34'), findsWidgets);
    await tester.scrollUntilVisible(find.text('손님0'), 200,
        scrollable: find.descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable)));
    expect(find.text('손님0'), findsOneWidget);
  });

  testWidgets('직접 입력 버튼 없이 금액칸에 적고 저장한다', (tester) async {
    final repo = await open(tester);
    expect(find.text('직접 입력'), findsNothing);
    final amount = find.widgetWithText(TextField, '금액 직접 입력');

    // 이름이 없으면 금액은 남겨 두고 이름부터 받는다
    await tester.enterText(amount, '70000');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(repo.entries, isEmpty);
    expect(find.text('이름을 먼저 입력해 주세요'), findsOneWidget);
    expect(tester.widget<TextField>(amount).controller!.text, '70,000');

    await tester.enterText(find.byType(TextField).first, '김철수');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(repo.entries.single.amount, 70000);
    expect(tester.widget<TextField>(amount).controller!.text, isEmpty);
    final name = tester.widget<TextField>(find.byType(TextField).first);
    expect(name.focusNode!.hasFocus, isTrue);

    // 키보드의 완료로도 저장된다
    await tester.enterText(find.byType(TextField).first, '이영희');
    await tester.enterText(amount, '30000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.entries.length, 2);
    expect(repo.entries.last.amount, 30000);
  });

  group('접수 시작 구분', () {
    Future<void> openForm(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
            theme: buildAppTheme(), home: const ReceptionFormScreen()),
      ));
      await tester.pumpAndSettle();
    }

    TextField sidesField(WidgetTester tester) =>
        tester.widget<TextField>(find.ancestor(
            of: find.text('구분 직접 입력'), matching: find.byType(TextField)));

    testWidgets('결혼: 입력칸은 비어 있고, 버튼과 직접 입력을 함께 쓴다', (tester) async {
      await openForm(tester);
      expect(sidesField(tester).controller!.text, isEmpty);
      expect(sidesField(tester).decoration!.hintText, '예: 신랑측, 신부측');

      await tester.tap(find.widgetWithText(OutlinedButton, '신부측'));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, '신랑측'));
      await tester.pump();
      expect(sidesField(tester).controller!.text, '신랑측, 신부측');

      await tester.enterText(find.byWidget(sidesField(tester)), '신랑측, 양가 어른');
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, '신랑측'));
      await tester.pump();
      expect(sidesField(tester).controller!.text, '양가 어른');
    });

    testWidgets('다른 종류: 버튼이 없고, 고른 신랑측 · 신부측은 빠진다', (tester) async {
      await openForm(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, '신랑측'));
      await tester.pump();
      await tester.tap(find.text('장례'));
      await tester.pump();
      expect(find.widgetWithText(OutlinedButton, '신랑측'), findsNothing);
      final field = tester.widget<TextField>(find.ancestor(
          of: find.text('상주 이름'), matching: find.byType(TextField)));
      expect(field.controller!.text, isEmpty);
    });
  });

  testWidgets('구분을 바꾸면 저장되는 구분도 바뀌고, 되돌리기로 지울 수 있다', (tester) async {
    final repo = await open(tester);

    await tester.tap(find.text('신부측'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '이영희');
    await tester.tap(find.text('20만'));
    await tester.pumpAndSettle();
    expect(repo.entries.single.side, '신부측');

    await tester.ensureVisible(find.text('되돌리기'));
    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    expect(repo.entries, isEmpty);
  });

  testWidgets('뒤로가기는 확인을 묻고, 접수 중에는 결제 화면이 뜨지 않는다', (tester) async {
    await open(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('접수를 잠시 멈출까요?'), findsOneWidget);
    expect(find.byType(ReceptionScreen), findsOneWidget);
    expect(find.byType(PaywallScreen), findsNothing);

    await tester.tap(find.text('멈추기'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceptionScreen), findsNothing);
  });

  group('받은 장부 가져오기 한도', () {
    Future<ImportFakeRepository> openImport(WidgetTester tester,
        {bool pro = false}) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(
          {if (pro) 'flutter.${PrefKeys.proPurchased}': true});
      final prefs = await SharedPreferences.getInstance();
      final repo = ImportFakeRepository();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: ReceptionImportScreen(package: repo.package),
        ),
      ));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('무료: 30명을 넘으면 안내와 결제 화면 → 닫으면 30명만 가져올지 묻는다', (tester) async {
      final repo = await openImport(tester);

      await tester.tap(find.text('31명 가져오기'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      expect(find.text('31명 중 30명까지 가져올 수 있어요.'), findsOneWidget);
      expect(repo.appliedLimits, isEmpty);

      await tester.ensureVisible(find.text('나중에 할게요'));
      await tester.tap(find.text('나중에 할게요'));
      await tester.pumpAndSettle();
      expect(find.text('30명만 먼저 가져올까요?'), findsOneWidget);

      await tester.tap(find.text('30명 가져오기'));
      await tester.pumpAndSettle();
      expect(repo.appliedLimits, [FreeLimits.people]);
      expect(find.text('30명을 가져왔어요'), findsOneWidget);
    });

    testWidgets('무료: 결제 화면을 닫고 취소하면 아무것도 저장하지 않는다', (tester) async {
      final repo = await openImport(tester);

      await tester.tap(find.text('31명 가져오기'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('나중에 할게요'));
      await tester.tap(find.text('나중에 할게요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(repo.appliedLimits, isEmpty);
    });

    testWidgets('프로: 결제 화면 없이 전부 가져온다', (tester) async {
      final repo = await openImport(tester, pro: true);

      await tester.tap(find.text('31명 가져오기'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
      expect(repo.appliedLimits, [null]);
      expect(find.text('31명을 가져왔어요'), findsOneWidget);
    });
  });

  testWidgets('접수 중에는 사람 40명을 넘게 받아도 결제 화면이 뜨지 않는다', (tester) async {
    final repo = await open(tester);
    for (var i = 0; i < 40; i++) {
      await tester.enterText(find.byType(TextField).first, '손님$i');
      await tester.tap(find.text('5만'));
      await tester.pumpAndSettle();
    }
    expect(repo.entries.length, 40);
    expect(find.byType(PaywallScreen), findsNothing);
  });
}
