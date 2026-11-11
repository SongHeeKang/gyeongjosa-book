// 추가 O: 카카오톡 등에서 장부 파일을 눌러 열면 바로 가져오기 화면으로 간다
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/providers.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/event.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/screens/reception_import_screen.dart';
import 'package:gyeongjosa/services/incoming_file_service.dart';
import 'package:gyeongjosa/services/reception_import.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _package = ReceptionPackage(
  Reception(
    id: 'r1',
    title: '누나 결혼식',
    eventType: '결혼',
    date: DateTime(2026, 12, 26),
    sides: const ['신부측'],
    operatorName: '송희강',
    startedAt: DateTime(2026, 12, 26),
  ),
  [
    for (var i = 0; i < 10; i++)
      ReceptionEntry(
        id: 'e$i',
        receptionId: 'r1',
        name: '손님$i',
        amount: 50000,
        side: '신부측',
        createdAt: DateTime(2026, 12, 26).add(Duration(minutes: i)),
      ),
  ],
);

class _FakeRepository extends Repository {
  _FakeRepository(this.people) : super(DatabaseHelper.forTest('unused.db'));
  final int people;
  @override
  Future<List<EventSummary>> eventSummaries() async => const [];
  @override
  Future<int> countMyEvents() async => 0;
  @override
  Future<int> countPeople() async => people;
  @override
  Future<Event?> getEvent(int id) async => null;
  @override
  Future<ImportPlan> planImport(ReceptionPackage package,
          {int? eventId, int? maxPeople}) async =>
      buildImportPlan(
        entries: package.entries,
        importedIds: const {},
        peopleByName: const {},
        namesInEvent: const {},
        newPersonSlots: maxPeople == null ? null : maxPeople - people,
      );
}

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('incoming'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester, {int people = 0}) async {
    tester.view.physicalSize = const Size(411 * 2, 914 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        repositoryProvider.overrideWithValue(_FakeRepository(people)),
      ],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        theme: buildAppTheme(),
        home: const Scaffold(body: Text('첫 화면')),
      ),
    ));
  }

  testWidgets('장부 파일이면 가져오기 미리보기와 무료로 가져올 수 있는 인원이 보인다', (tester) async {
    await pump(tester, people: 25);
    final file = File('${dir.path}/ledger.json')
      ..writeAsStringSync(_package.toJsonString());
    await tester.runAsync(() => IncomingFiles.open(file.path).timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {})); // push가 끝나기(화면을 닫기)를 기다리지 않는다
    await tester.pumpAndSettle();
    expect(find.byType(ReceptionImportScreen), findsOneWidget);
    expect(find.text('누나 결혼식'), findsWidgets);
    expect(find.text('무료로 5명까지 가져올 수 있어요'), findsOneWidget);

    // 뒤로 가면 원래 화면(첫 실행 가이드 등)으로 돌아간다
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('첫 화면'), findsOneWidget);
  });

  testWidgets('장부 파일이 아니면 안내만 하고 아무것도 바꾸지 않는다', (tester) async {
    await pump(tester);
    final file = File('${dir.path}/photo.json')..writeAsStringSync('{"a":1}');
    await tester.runAsync(() => IncomingFiles.open(file.path).timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {}));
    await tester.pumpAndSettle();
    expect(find.byType(ReceptionImportScreen), findsNothing);
    expect(find.text('경조사 장부 파일이 아니에요. 기존 기록은 그대로예요.'), findsOneWidget);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    // 읽지 못한 파일(빈 경로)도 같은 안내
    await tester.runAsync(() => IncomingFiles.open('').timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {}));
    await tester.pumpAndSettle();
    expect(find.text('경조사 장부 파일이 아니에요. 기존 기록은 그대로예요.'), findsOneWidget);
  });
}
