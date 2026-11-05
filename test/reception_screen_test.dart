import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/providers.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/event.dart';
import 'package:gyeongjosa/models/constants.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/screens/paywall_screen.dart';
import 'package:gyeongjosa/screens/reception_form_screen.dart';
import 'package:gyeongjosa/screens/reception_import_screen.dart';
import 'package:gyeongjosa/screens/reception_screen.dart';
import 'package:gyeongjosa/services/limits.dart';
import 'package:gyeongjosa/services/reception_import.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:gyeongjosa/widgets/amount_input.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 화면 동작만 확인하는 메모리 저장소
class FakeRepository extends Repository {
  FakeRepository() : super(DatabaseHelper.forTest('unused.db'));

  Reception reception = Reception(
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
  Future<void> setReceptionMealTicketEnabled(String id, bool enabled) async =>
      reception = reception.copyWith(mealTicketEnabled: enabled);

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

  Future<FakeRepository> open(
    WidgetTester tester, {
    bool mealTicketEnabled = true,
    int defaultMealTickets = 1,
    bool methodEnabled = true,
    double width = 1080,
  }) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeRepository();
    repo.reception = Reception(
      id: 'r1',
      title: '홍길동 결혼식',
      eventType: '결혼',
      date: DateTime(2026, 11, 1),
      sides: const ['신랑측', '신부측'],
      operatorName: '김민수',
      startedAt: DateTime(2026, 11, 1, 9),
      mealTicketEnabled: mealTicketEnabled,
      defaultMealTickets: defaultMealTickets,
      methodEnabled: methodEnabled,
    );
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

  group('금액칸', () {
    Finder amountField() => find.widgetWithText(TextField, '금액');

    testWidgets('만원 단위로 적고 키보드 완료로 저장하고, 커서는 이름칸으로', (tester) async {
      final repo = await open(tester);
      expect(find.text('직접 입력'), findsNothing);

      // 이름이 없으면 금액은 남겨 두고 이름부터 받는다
      await tester.enterText(amountField(), '7');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(repo.entries, isEmpty);
      expect(find.text('이름을 먼저 입력해 주세요'), findsOneWidget);
      expect(tester.widget<TextField>(amountField()).controller!.text, '7');

      await tester.enterText(find.byType(TextField).first, '김철수');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(amountField()).focusNode!.hasFocus, isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(repo.entries.single.amount, 70000);
      expect(tester.widget<TextField>(amountField()).controller!.text, isEmpty);
      final name = tester.widget<TextField>(find.byType(TextField).first);
      expect(name.focusNode!.hasFocus, isTrue);
    });

    testWidgets('3.5는 35,000원, 70000처럼 큰 수는 저장하지 않고 안내한다', (tester) async {
      final repo = await open(tester);
      await tester.enterText(find.byType(TextField).first, '이영희');
      await tester.enterText(amountField(), '3.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(repo.entries.single.amount, 35000);

      await tester.enterText(find.byType(TextField).first, '박민수');
      await tester.enterText(amountField(), '70000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(repo.entries.length, 1);
      expect(find.text('금액은 만원 단위로 입력해요. 7 → 70,000원'), findsOneWidget);
    });

    test('만원 환산', () {
      expect(parseManWon('7'), 70000);
      expect(parseManWon('3.5'), 35000);
      expect(parseManWon('.5'), 5000);
      expect(parseManWon('1.2345'), 12345);
      expect(parseManWon(''), 0);
    });
  });

  group('식권 · 계좌 칩', () {
    testWidgets('칩을 고르면 이번 손님만 적용되고 저장 뒤 기본값으로 돌아간다', (tester) async {
      final repo = await open(tester);
      await tester.enterText(find.byType(TextField).first, '김철수');
      await tester.tap(find.widgetWithText(OutlinedButton, '3'));
      await tester.tap(find.widgetWithText(OutlinedButton, '계좌'));
      await tester.pump();
      await tester.tap(find.text('5만'));
      await tester.pumpAndSettle();
      expect(repo.entries.single.mealTickets, 3);
      expect(repo.entries.single.method, ReceptionDefaults.transfer);
      expect(find.textContaining('김철수 · 5만 · 식권 3 · 계좌'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '이영희');
      await tester.tap(find.text('10만'));
      await tester.pumpAndSettle();
      expect(repo.entries.last.mealTickets, 1);
      expect(repo.entries.last.method, ReceptionDefaults.cash);
    });

    testWidgets('4+는 누를 때마다 한 장씩 늘어난다', (tester) async {
      final repo = await open(tester);
      await tester.enterText(find.byType(TextField).first, '김철수');
      await tester.tap(find.widgetWithText(OutlinedButton, '4+'));
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, '4+'));
      await tester.pump();
      await tester.tap(find.text('5만'));
      await tester.pumpAndSettle();
      expect(repo.entries.single.mealTickets, 5);
    });

    testWidgets('식권 기록과 계좌 구분을 끄면 칩이 없고 식권은 0으로 저장된다', (tester) async {
      final repo = await open(tester,
          mealTicketEnabled: false, methodEnabled: false);
      expect(find.text('식권'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '4+'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '계좌'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '김철수');
      await tester.tap(find.text('5만'));
      await tester.pumpAndSettle();
      expect(repo.entries.single.mealTickets, 0);
      expect(find.textContaining('식권 0'), findsNothing);
      expect(find.textContaining('김철수 · 5만 · '), findsWidgets);
    });

    testWidgets('기본 매수 2면 2가 선택되어 저장되고, 접수 중에 끌 수 있다', (tester) async {
      final repo = await open(tester, defaultMealTickets: 2);
      await tester.enterText(find.byType(TextField).first, '김철수');
      await tester.tap(find.text('5만'));
      await tester.pumpAndSettle();
      expect(repo.entries.single.mealTickets, 2);

      await tester.tap(find.text('식권 끄기'));
      await tester.pumpAndSettle();
      expect(repo.reception.mealTicketEnabled, isFalse);
      expect(find.widgetWithText(OutlinedButton, '4+'), findsNothing);
      expect(find.text('식권 켜기'), findsOneWidget);
      // 이미 저장한 항목은 그대로
      expect(repo.entries.single.mealTickets, 2);
    });

    testWidgets('좁은 폰에서는 칩이 윗줄로 올라가고 넘치지 않는다', (tester) async {
      await open(tester, width: 360 * 2.625);
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(OutlinedButton, '4+'), findsOneWidget);
      expect(tester.getTopLeft(find.widgetWithText(OutlinedButton, '4+')).dy,
          lessThan(tester.getTopLeft(find.widgetWithText(TextField, '금액')).dy));
    });
  });

  group('접수 시작 구분', () {
    Future<void> openForm(WidgetTester tester) async {
      // 접수 시작 버튼까지 한 화면에 보이도록 세로를 넉넉하게
      tester.view.physicalSize = const Size(1080, 4000);
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
      expect(sidesField(tester).decoration!.hintText, '예: 신랑측, 신부측 / 상주 이름');

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

    testWidgets('식권과 결제 방법을 모두 골라야 접수 시작이 눌린다', (tester) async {
      await openForm(tester);
      FilledButton start() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '접수 시작'));
      expect(start().onPressed, isNull);
      expect(find.text('1매'), findsNothing);

      await tester.ensureVisible(find.text('식권도 기록'));
      await tester.tap(find.text('식권도 기록'));
      await tester.pump();
      expect(find.text('2매'), findsOneWidget);
      expect(start().onPressed, isNull);

      await tester.ensureVisible(find.text('현금만'));
      await tester.tap(find.text('현금만'));
      await tester.pump();
      expect(start().onPressed, isNotNull);
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
