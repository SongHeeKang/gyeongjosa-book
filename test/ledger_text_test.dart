
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/models/constants.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/services/ledger_text_format.dart';
import 'package:intl/date_symbol_data_local.dart';

Reception otherEvent({bool meals = true, bool method = true}) => Reception(
      id: 'r1',
      title: '누나 결혼식',
      eventType: '결혼',
      date: DateTime(2026, 12, 26),
      sides: const ['신랑측', '신부측'],
      operatorName: '송희강',
      startedAt: DateTime(2026, 12, 26, 11),
      mealTicketEnabled: meals,
      methodEnabled: method,
    );

/// [count]명: 이름은 받은 순서와 가나다순이 다르게 섞는다.
ReceptionPackage bigPackage(int count) => ReceptionPackage(otherEvent(), [
      for (var i = 0; i < count; i++)
        ReceptionEntry(
          id: 'e$i',
          receptionId: 'r1',
          name: '손님${(count - i).toString().padLeft(3, '0')}',
          amount: 50000 + (i % 5) * 10000,
          side: i.isEven ? '신랑측' : '신부측',
          method: i % 7 == 0 ? ReceptionDefaults.transfer : ReceptionDefaults.cash,
          mealTickets: i % 3,
          memo: i % 10 == 0 ? '봉투 $i' : null,
          createdAt: DateTime(2026, 12, 26, 11).add(Duration(minutes: i)),
        ),
    ]);

/// 비교용: 이름 · 금액 · 구분 · 방법 · 식권 · 메모
List<String> rows(ReceptionPackage p) => [
      for (final e in LedgerText.sorted(p.entries, LedgerOrder.name))
        [e.name, e.amount, e.side, e.method, e.mealTickets, e.memo ?? '']
            .join('|'),
    ];

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  group('보낼 글', () {
    test('기획서 예시 모양: 머리말 · 합계 · 명단 · 앱 안내', () {
      final package = ReceptionPackage(otherEvent(), [
        ReceptionEntry(
            id: 'a',
            receptionId: 'r1',
            name: '강지은',
            amount: 50000,
            side: '신부측',
            method: ReceptionDefaults.transfer,
            mealTickets: 2,
            memo: '봉투 2개',
            createdAt: DateTime(2026, 12, 26, 12)),
        ReceptionEntry(
            id: 'b',
            receptionId: 'r1',
            name: '강민호',
            amount: 100000,
            side: '신랑측',
            mealTickets: 0,
            createdAt: DateTime(2026, 12, 26, 11)),
      ]);
      final text = LedgerText.build(package, storeUrl: 'URL').single;
      expect(
          text,
          [
            '[경조사 장부] 누나 결혼식 받은 명단',
            '2026년 12월 26일 (토) · 받은 사람: 송희강',
            '',
            '총 2명 · 150,000원',
            '- 신랑측 1명 · 100,000원',
            '- 신부측 1명 · 50,000원',
            '현금 100,000원 · 계좌 50,000원 · 식권 2장',
            '',
            '1. 강민호 · 100,000원 · 신랑측 · 현금 · 오전 11:00',
            '2. 강지은 · 50,000원 · 신부측 · 계좌 · 식권 2 · 오후 12:00 · 메모: 봉투 2개',
            '',
            '경조사 장부 앱으로 정리했어요',
            '앱 받기: URL',
          ].join('\n'));

      // 받은 순서 · 메모 빼기
      final received = LedgerText.build(package,
              order: LedgerOrder.received, includeMemo: false)
          .single;
      expect(received, contains('1. 강민호'));
      expect(received, contains('2. 강지은 · 50,000원 · 신부측 · 계좌 · 식권 2 · 오후 12:00\n'));
      expect(received, isNot(contains('메모')));
    });

    test('값이 없는 항목은 뺀다: 구분 없음 · 현금만 · 식권 없음 · 받은 사람 없음', () {
      final package = ReceptionPackage(
        Reception(
          id: 'r',
          title: '우리 돌잔치',
          eventType: '돌',
          date: DateTime(2026, 11, 1),
          sides: const [ReceptionDefaults.noSide],
          operatorName: '',
          startedAt: DateTime(2026, 11, 1),
          mealTicketEnabled: false,
          methodEnabled: false,
        ),
        [
          ReceptionEntry(
              id: 'a',
              receptionId: 'r',
              name: '김철수',
              amount: 30000,
              side: ReceptionDefaults.noSide,
              mealTickets: 0,
              createdAt: DateTime(2026, 11, 1)),
        ],
      );
      final text = LedgerText.build(package, storeUrl: 'URL').single;
      expect(text, startsWith('[경조사 장부] 우리 돌잔치 받은 명단\n2026년 11월 1일 (일)\n\n총 1명 · 30,000원\n\n1. 김철수 · 30,000원\n'));
      expect(text, isNot(contains('- ')));
      expect(text, isNot(contains('현금')));
      expect(text, isNot(contains('식권')));
    });

    test('이름 · 메모의 구분 기호(·)와 줄바꿈은 바꿔서 보낸다', () {
      final package = ReceptionPackage(otherEvent(method: false), [
        ReceptionEntry(
            id: 'a',
            receptionId: 'r1',
            name: '김·철수',
            amount: 50000,
            side: '신랑측',
            mealTickets: 1,
            memo: '회사 · 동기\n둘째 줄',
            createdAt: DateTime(2026, 12, 26)),
      ]);
      final text = LedgerText.build(package).single;
      expect(text, contains('1. 김-철수 · 50,000원 · 신랑측 · 식권 1 · 메모: 회사 - 동기 둘째 줄'));
    });

    test('100명을 넘으면 100명씩 나누고, 메시지마다 머리말 · 합계 · 이어짐 표시', () {
      final package = bigPackage(250);
      final parts = LedgerText.build(package);
      expect(parts.length, 3);
      expect(kShareChunkSize, 100);
      for (final (i, text) in parts.indexed) {
        expect(text, startsWith('[경조사 장부] 누나 결혼식 받은 명단 (${i + 1}/3)'));
        expect(text, contains('총 250명 · '));
        expect(text, contains('- 신랑측 125명'));
        expect(text, contains(LedgerText.guideLine));
      }
      expect(parts[0], contains('\n1. '));
      expect(parts[0], contains('\n100. '));
      expect(parts[0], contains('(1/3) 다음 메시지에 이어져요'));
      expect(parts[1], contains('\n101. '));
      expect(parts[1], contains('(2/3) 다음 메시지에 이어져요'));
      expect(parts[2], contains('\n250. '));
      expect(parts[2], isNot(contains('다음 메시지에 이어져요')));
      expect(LedgerText.build(bigPackage(100)).length, 1);
    });
  });

}
