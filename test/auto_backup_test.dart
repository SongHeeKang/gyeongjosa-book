import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/providers.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/screens/restore_prompt.dart';
import 'package:gyeongjosa/services/auto_backup_service.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepository extends Repository {
  _FakeRepository() : super(DatabaseHelper.forTest('unused.db'));
  bool hasData = true;

  @override
  Future<bool> hasAnyData() async => hasData;
}

class _FakeWriter extends AutoBackupWriter {
  final saves = <({String fileName, String? replaceName})>[];
  bool fail = false;

  @override
  Future<String> save(Repository repository,
      {required String fileName, String? replaceName}) async {
    if (fail) throw Exception('저장 실패');
    saves.add((fileName: fileName, replaceName: replaceName));
    return replaceName ?? fileName;
  }
}

void main() {
  test('파일 이름에 날짜가 들어간다', () {
    expect(autoBackupFileName(DateTime(2026, 11, 5)), '경조사장부_백업_20261105.db');
  });

  test('오늘 이번 장부에서 만든 파일만 덮어쓴다', () {
    const today = '경조사장부_백업_20261105.db';
    expect(autoBackupReplaceName(null, today), isNull);
    expect(autoBackupReplaceName('경조사장부_백업_20261104.db', today), isNull);
    expect(autoBackupReplaceName(today, today), today);
    expect(autoBackupReplaceName('경조사장부_백업_20261105 (1).db', today),
        '경조사장부_백업_20261105 (1).db');
  });

  group('자동 백업 시점', () {
    late _FakeRepository repo;
    late _FakeWriter writer;
    late ProviderContainer container;

    Future<void> setUpContainer(WidgetTester tester,
        [Map<String, Object> prefsValues = const {}]) async {
      SharedPreferences.setMockInitialValues(
          {for (final e in prefsValues.entries) 'flutter.${e.key}': e.value});
      final prefs = await SharedPreferences.getInstance();
      repo = _FakeRepository();
      writer = _FakeWriter();
      container = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(prefs),
        repositoryProvider.overrideWithValue(repo),
        autoBackupWriterProvider.overrideWithValue(writer),
      ]);
      addTearDown(container.dispose);
      container.read(autoBackupProvider);
    }

    void change() => container.read(dbVersionProvider.notifier).bump();

    testWidgets('연속으로 저장하면 마지막 변경 5초 뒤에 한 번만 백업한다', (tester) async {
      await setUpContainer(tester);
      for (var i = 0; i < 5; i++) {
        change();
        await tester.pump(const Duration(seconds: 3));
        expect(writer.saves, isEmpty);
      }
      await tester.pump(const Duration(seconds: 2));
      expect(writer.saves.length, 1);
      expect(container.read(autoBackupProvider).lastAt, isNotNull);
    });

    testWidgets('저장이 끝없이 이어져도 60초마다는 백업한다', (tester) async {
      await setUpContainer(tester);
      for (var i = 0; i < 21; i++) {
        change();
        await tester.pump(const Duration(seconds: 3));
      }
      expect(writer.saves.length, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(writer.saves.length, 2);
    });

    testWidgets('앱이 뒤로 가면 기다리지 않고 바로 백업한다', (tester) async {
      await setUpContainer(tester);
      await container.read(autoBackupProvider.notifier).flush();
      expect(writer.saves, isEmpty, reason: '기다리는 변경이 없으면 하지 않는다');
      change();
      await tester.pump();
      await container.read(autoBackupProvider.notifier).flush();
      expect(writer.saves.length, 1);
    });

    testWidgets('빈 장부로는 백업하지 않는다', (tester) async {
      await setUpContainer(tester);
      repo.hasData = false;
      change();
      await tester.pump(const Duration(seconds: 5));
      expect(writer.saves, isEmpty);
    });

    testWidgets('끄면 백업하지 않고, 기본값은 켜짐이다', (tester) async {
      await setUpContainer(tester);
      expect(container.read(autoBackupProvider).enabled, isTrue);
      change();
      await container.read(autoBackupProvider.notifier).setEnabled(false);
      await tester.pump(const Duration(seconds: 70));
      change();
      await tester.pump(const Duration(seconds: 70));
      expect(writer.saves, isEmpty);
    });

    testWidgets('두 번째 저장은 오늘 파일을 바꾸고, 복원 뒤에는 새 파일로 남긴다', (tester) async {
      await setUpContainer(tester);
      change();
      await tester.pump(const Duration(seconds: 5));
      expect(writer.saves.last.replaceName, isNull);

      change();
      await tester.pump(const Duration(seconds: 5));
      expect(writer.saves.last.replaceName, writer.saves.first.fileName);

      await container.read(autoBackupProvider.notifier).beforeRestore();
      change();
      await tester.pump(const Duration(seconds: 5));
      expect(writer.saves.last.replaceName, isNull);
    });

    testWidgets('실패하면 표시하고 다음 변경 때 다시 시도한다', (tester) async {
      await setUpContainer(tester);
      writer.fail = true;
      change();
      await tester.pump(const Duration(seconds: 5));
      expect(container.read(autoBackupProvider).failed, isTrue);

      writer.fail = false;
      change();
      await tester.pump(const Duration(seconds: 5));
      expect(container.read(autoBackupProvider).failed, isFalse);
      expect(writer.saves.length, 1);
    });
  });

  group('이전 백업 불러오기 안내', () {
    Future<_FakeRepository> pump(WidgetTester tester,
        {bool hasData = false, bool done = false}) async {
      SharedPreferences.setMockInitialValues(
          {if (done) 'flutter.${PrefKeys.restorePromptDone}': true});
      final prefs = await SharedPreferences.getInstance();
      final repo = _FakeRepository()..hasData = hasData;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
            theme: buildAppTheme(),
            home: const RestorePromptGate(child: Scaffold())),
      ));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('기록이 비어 있으면 묻고, 새로 시작하면 다시 묻지 않는다', (tester) async {
      await pump(tester);
      expect(find.text('이전 백업을 불러올까요?'), findsOneWidget);
      expect(find.text('백업 파일 고르기'), findsOneWidget);

      await tester.tap(find.text('새로 시작'));
      await tester.pumpAndSettle();
      expect(find.text('이전 백업을 불러올까요?'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PrefKeys.restorePromptDone), isTrue);
    });

    testWidgets('기록이 있거나 이미 답했으면 묻지 않는다', (tester) async {
      await pump(tester, hasData: true);
      expect(find.text('이전 백업을 불러올까요?'), findsNothing);
      await pump(tester, done: true);
      expect(find.text('이전 백업을 불러올까요?'), findsNothing);
    });
  });
}
