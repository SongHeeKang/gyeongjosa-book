// 추가 R: 장부 보내기는 저장된 모든 값을 글자 하나로 보낸다 (100명씩 나눠 보내기, 파일 없음)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/providers.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/screens/reception_send_screen.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReceptionPackage _package(List<String> names, {String? memo}) => ReceptionPackage(
      Reception(
        id: 'r1',
        title: '홍길동 결혼식',
        eventType: '결혼',
        date: DateTime(2026, 11, 15),
        sides: const ['신랑측', '신부측'],
        operatorName: '박지원',
        startedAt: DateTime(2026, 11, 15),
        mealTicketEnabled: false,
        methodEnabled: false,
      ),
      [
        for (final (i, name) in names.indexed)
          ReceptionEntry(
            id: 'e$i',
            receptionId: 'r1',
            name: name,
            amount: 50000,
            side: i.isEven ? '신랑측' : '신부측',
            mealTickets: 0,
            memo: i == 0 ? memo : null,
            createdAt: DateTime(2026, 11, 15, 12, i),
          ),
      ],
    );

class _FakeRepository extends Repository {
  _FakeRepository() : super(DatabaseHelper.forTest('unused.db'));
  final deleted = <String>[];
  @override
  Future<void> deleteReception(String id) async => deleted.add(id);
}

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  late List<String> shared;
  late _FakeRepository repo;

  Future<void> open(WidgetTester tester, ReceptionPackage package,
      {String? receptionId}) async {
    tester.view.physicalSize = const Size(411 * 2, 914 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    shared = [];
    ReceptionSendScreen.debugShare = (text) async {
      shared.add(text);
      return true;
    };
    addTearDown(() => ReceptionSendScreen.debugShare = null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = _FakeRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        repositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => ReceptionSendScreen(
                            package: package, receptionId: receptionId))),
                child: const Text('시작'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();
  }

  String preview(WidgetTester tester) =>
      tester.widget<SelectableText>(find.byType(SelectableText)).data!;

  testWidgets('보낼 글 미리보기: 가나다순이 기본, 받은 순서로 바꿀 수 있고 파일 · 요약 선택은 없다',
      (tester) async {
    await open(tester, _package(['황지수', '강민호', '고현우']));
    final text = preview(tester);
    expect(text, startsWith('[경조사 장부] 홍길동 결혼식 받은 명단\n'));
    expect(text, contains('총 3명 · 150,000원'));
    expect(text, contains('1. 강민호 · 50,000원 · 신부측'));
    expect(text, contains('3. 황지수 · 50,000원 · 신랑측'));
    expect(text, contains('경조사 장부 앱으로 정리했어요'));
    expect(text, isNot(contains('가져오기')));
    expect(find.text('장부 파일'), findsNothing);
    expect(find.text('요약 메시지'), findsNothing);
    // 메모가 없으면 [메모 포함]도 없다
    expect(find.text('메모 포함'), findsNothing);

    await tester.tap(find.text('받은 순서'));
    await tester.pumpAndSettle();
    expect(preview(tester), contains('1. 황지수'));
  });

  testWidgets('[복사]는 글을 복사하고, [보내기]는 글자만 공유창으로 보낸다', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await open(tester, _package(['강민호']));
    await tester.tap(find.text('복사'));
    await tester.pumpAndSettle();
    expect(copied, preview(tester));

    await tester.tap(find.text('보내기'));
    await tester.pumpAndSettle();
    expect(shared, [preview(tester)]);
    expect(find.text('보냈어요 · 다시 보내기'), findsOneWidget);
    // 내 행사(장부 id 없음)는 보관 · 지우기를 묻지 않는다
    expect(find.text('이 장부를 보관할까요, 지울까요?'), findsNothing);
  });

  testWidgets('[메모 포함]을 끄면 메모가 빠진다', (tester) async {
    await open(tester, _package(['강민호', '고현우'], memo: '봉투 2개'));
    expect(preview(tester), contains('메모: 봉투 2개'));
    await tester.tap(find.text('메모 포함'));
    await tester.pumpAndSettle();
    expect(preview(tester), isNot(contains('메모')));
  });

  testWidgets('120명: [1/2] [2/2] 차례로, 둘 다 합계 포함, 다 보내면 보관 · 지우기 (보관)',
      (tester) async {
    final names = [for (var i = 0; i < 120; i++) '손님${i.toString().padLeft(3, '0')}'];
    await open(tester, _package(names), receptionId: 'r1');
    expect(find.text('1/2 보내기'), findsOneWidget);
    expect(find.text('2/2 보내기'), findsOneWidget);
    expect(preview(tester), startsWith('[경조사 장부] 홍길동 결혼식 받은 명단 (1/2)'));

    await tester.tap(find.text('1/2 보내기'));
    await tester.pumpAndSettle();
    expect(find.text('1/2 보냈어요 ✓'), findsOneWidget);
    expect(find.text('이 장부를 보관할까요, 지울까요?'), findsNothing);
    // 다음에 보낼 글로 미리보기가 넘어간다
    expect(preview(tester), startsWith('[경조사 장부] 홍길동 결혼식 받은 명단 (2/2)'));

    await tester.tap(find.text('2/2 보내기'));
    await tester.pumpAndSettle();
    expect(shared.length, 2);
    for (final text in shared) {
      expect(text, contains('총 120명 · 6,000,000원'));
      expect(text, contains('- 신랑측 60명 · 3,000,000원'));
    }
    expect(shared[0], contains('(1/2) 다음 메시지에 이어져요'));
    expect(shared[1], contains('\n120. 손님119'));
    expect(find.text('이 장부를 보관할까요, 지울까요?'), findsOneWidget);
    await tester.tap(find.text('보관'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);
    expect(find.byType(ReceptionSendScreen), findsOneWidget);
  });

  testWidgets('다른 사람 행사 [지우기]는 한 번 더 확인한 뒤 지운다', (tester) async {
    await open(tester, _package(['강민호']), receptionId: 'r1');
    await tester.tap(find.text('보내기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지우기'));
    await tester.pumpAndSettle();
    expect(find.text('장부를 지울까요?'), findsOneWidget);
    expect(repo.deleted, isEmpty);
    await tester.tap(find.text('지우기').last);
    await tester.pumpAndSettle();
    expect(repo.deleted, ['r1']);
    expect(find.byType(ReceptionSendScreen), findsNothing);
    expect(find.text('장부를 지웠어요.'), findsOneWidget);
  });
}
