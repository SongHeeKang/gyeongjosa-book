// 추가 L: 장부 보내기 전에 받는 사람에게 무엇이 보이는지 보여준다
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/screens/reception_send_screen.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:intl/date_symbol_data_local.dart';

final _package = ReceptionPackage(
  Reception(
    id: 'r1',
    title: '홍길동 결혼식',
    eventType: '결혼',
    date: DateTime(2026, 11, 15),
    sides: const ['신랑측', '신부측'],
    operatorName: '박지원',
    startedAt: DateTime(2026, 11, 15),
  ),
  [
    for (final (i, name) in ['강민호', '강지은', '고현우', '황지수'].indexed)
      ReceptionEntry(
        id: 'e$i',
        receptionId: 'r1',
        name: name,
        amount: 50000,
        side: i.isEven ? '신랑측' : '신부측',
        createdAt: DateTime(2026, 11, 15, 12, i),
      ),
  ],
);

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411 * 2, 914 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(), home: ReceptionSendScreen(package: _package)));
    await tester.pumpAndSettle();
  }

  testWidgets('두 카드에 받는 사람 화면 예시가 있고, 처음에는 추천인 장부 파일이 골라져 있다',
      (tester) async {
    await open(tester);
    // 요약 메시지 카드: 인원 · 총액 · 구분별 소계 + 명단 없음
    expect(find.text('총 4명 · 200,000원'), findsOneWidget);
    expect(find.text('신랑측 2명 · 100,000원'), findsOneWidget);
    expect(find.text('명단 없음 · 인원과 총액만'), findsOneWidget);
    // 장부 파일 카드: 이름 · 금액 줄 + 전체 명단 + 추천
    expect(find.text('강민호 · 50,000원'), findsOneWidget);
    expect(find.text('… 외 1명'), findsOneWidget);
    expect(find.text('전체 명단 · 앱에서 열기'), findsOneWidget);
    expect(find.text('추천'), findsOneWidget);

    // 받는 사람은 이렇게 열어요 (추가 O)
    expect(find.text('받는 사람은 이렇게 열어요'), findsOneWidget);
    expect(find.text("② 파일을 눌러 '경조사 장부'로 열기"), findsOneWidget);
    expect(find.text('무료는 30명까지 가져올 수 있어요(이 장부 4명)'), findsOneWidget);
    expect(find.text('카카오톡 파일은 보관 기간이 지나면 받을 수 없어요'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('요약 메시지만'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('안내 메시지 + 장부 파일 보내기'), findsOneWidget);
    expect(find.text('장부 파일만'), findsOneWidget);
    expect(find.text('장부 파일도 보내기'), findsNothing);
  });

  testWidgets('추천 버튼: 안내 메시지를 먼저 보내고 돌아오면 장부 파일 보내기가 나온다 (제목 없이)',
      (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'), (call) async {
      calls.add(call);
      return 'com.kakao.talk';
    });
    await open(tester);
    expect(find.text('② 이제 장부 파일을 같은 방에 보내세요'), findsNothing);
    await tester.scrollUntilVisible(find.text('안내 메시지 + 장부 파일 보내기'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('안내 메시지 + 장부 파일 보내기'));
    await tester.pumpAndSettle();

    final args = calls.single.arguments as Map;
    expect(args['text'], contains('[장부 파일 받는 방법]'));
    expect(args['subject'], isNull);
    await tester.scrollUntilVisible(find.text('② 이제 장부 파일을 같은 방에 보내세요'), -200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('② 이제 장부 파일을 같은 방에 보내세요'), findsOneWidget);
  });

  testWidgets('요약 메시지를 고르면 보낼 글 전체와 명단이 없다는 안내, 장부 파일도 보내기',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('요약 메시지'));
    await tester.pumpAndSettle();
    expect(find.textContaining('[경조사 장부] 홍길동 결혼식 접수 결과'), findsOneWidget);
    // 공유 버튼 근처는 화면 아래쪽이라 스크롤해서 본다
    await tester.scrollUntilVisible(find.text('요약 메시지 보내기'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('이 메시지에는 손님 명단이 들어가지 않아요. 명단까지 넘겨주려면 장부 파일을 함께 보내세요'),
        findsOneWidget);
    expect(find.text('장부 파일도 보내기'), findsOneWidget);
    expect(find.text('요약 메시지 보내기'), findsOneWidget);
    expect(find.textContaining("앱에서 열어야 명단이 보여요"), findsNothing);
  });
}
