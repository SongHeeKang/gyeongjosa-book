import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/person.dart';
import 'package:gyeongjosa/screens/manage_space_screen.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('manage_space'));
  tearDown(() => dir.deleteSync(recursive: true));

  Person person(String name) =>
      Person(name: name, relation: '친구', createdAt: DateTime(2026, 11, 5));

  test('DB를 닫지 않고 복사하고, 복사본은 복원 검사를 통과한다', () async {
    final helper = DatabaseHelper.forTest(p.join(dir.path, 'a.db'));
    final repo = Repository(helper);
    await repo.insertPerson(person('김철수'));

    final out = p.join(dir.path, 'copy.db');
    await helper.snapshotTo(out);
    await repo.insertPerson(person('이영희')); // 복사 뒤에도 그대로 쓸 수 있다
    expect(await repo.countPeople(), 2);
    await helper.close();

    await DatabaseHelper.validateBackupFile(out);
    final copy = Repository(DatabaseHelper.forTest(out));
    expect(await copy.countPeople(), 1);
  });

  group('데이터 관리 화면', () {
    late List<String> calls;
    late bool backedUp;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      calls = [];
      backedUp = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('gyeongjosa/manage_space'), (call) async {
        calls.add(call.method);
        return true;
      });
      final helper = DatabaseHelper.forTest(p.join(dir.path, 'b.db'));
      await tester.runAsync(() async {
        await Repository(helper).insertPerson(person('김철수'));
      });
      // 실제 DB를 쓰므로 화면도 실제 시간 안에서 띄운다
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: ManageSpaceScreen(
            helper: helper,
            onBackup: () async {
              backedUp = true;
              return true;
            },
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('사람 수 · 기록 수와 안내, 버튼 3개가 보인다', (tester) async {
      await open(tester);
      expect(find.text('사람 1명 · 기록 0건'), findsOneWidget);
      expect(find.text('앱 데이터를 지우면 모든 경조사 기록이 사라져요. 먼저 백업해 두세요'),
          findsOneWidget);
      for (final label in ['백업 파일 만들기', '취소', '그래도 모두 삭제']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('한 번 더 확인해야 지우고, 취소하면 지우지 않는다', (tester) async {
      await open(tester);
      await tester.tap(find.text('그래도 모두 삭제'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      await tester.tap(find.text('그래도 모두 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('모두 삭제'));
      await tester.pumpAndSettle();
      expect(calls, ['clearAppData']);
    });

    testWidgets('백업 파일 만들기를 누르면 백업한다', (tester) async {
      await open(tester);
      await tester.tap(find.text('백업 파일 만들기'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(backedUp, isTrue);
    });
  });
}
