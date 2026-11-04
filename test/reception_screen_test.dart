import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/providers.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/screens/paywall_screen.dart';
import 'package:gyeongjosa/screens/reception_screen.dart';
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

    await tester.enterText(find.byType(TextField), '김철수');
    await tester.tap(find.text('5만원'));
    await tester.pumpAndSettle();

    expect(repo.entries.single.name, '김철수');
    expect(repo.entries.single.amount, 50000);
    expect(repo.entries.single.side, '신랑측');
    expect(repo.entries.single.mealTickets, 1);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(find.text('1명 · 50,000원'), findsOneWidget);
  });

  testWidgets('이름 없이 금액을 누르면 저장하지 않고 안내한다', (tester) async {
    final repo = await open(tester);

    await tester.tap(find.text('10만원'));
    await tester.pumpAndSettle();

    expect(repo.entries, isEmpty);
    expect(find.text('이름을 먼저 입력해 주세요'), findsOneWidget);
  });

  testWidgets('같은 이름은 경고만 하고 저장은 막지 않는다', (tester) async {
    final repo = await open(tester);

    await tester.enterText(find.byType(TextField), '김철수');
    await tester.tap(find.text('5만원'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '김철수');
    await tester.pumpAndSettle();
    expect(find.text('같은 이름이 있어요'), findsOneWidget);

    await tester.tap(find.text('3만원'));
    await tester.pumpAndSettle();
    expect(repo.entries.length, 2);
  });

  testWidgets('구분을 바꾸면 저장되는 구분도 바뀌고, 되돌리기로 지울 수 있다', (tester) async {
    final repo = await open(tester);

    await tester.tap(find.text('신부측'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '이영희');
    await tester.tap(find.text('20만원'));
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

  testWidgets('접수 중에는 사람 40명을 넘게 받아도 결제 화면이 뜨지 않는다', (tester) async {
    final repo = await open(tester);
    for (var i = 0; i < 40; i++) {
      await tester.enterText(find.byType(TextField), '손님$i');
      await tester.tap(find.text('5만원'));
      await tester.pumpAndSettle();
    }
    expect(repo.entries.length, 40);
    expect(find.byType(PaywallScreen), findsNothing);
  });
}
