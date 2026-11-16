import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/constants.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/services/ledger_text_format.dart';
import 'package:gyeongjosa/services/limits.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
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
            '1. 강민호 · 100,000원 · 신랑측 · 현금',
            '2. 강지은 · 50,000원 · 신부측 · 계좌 · 식권 2 · 메모: 봉투 2개',
            '',
            "앱으로 정리하려면 이 메시지를 복사해 '경조사 장부' 앱 > 장부 가져오기 > [붙여넣어 가져오기]",
            '앱 받기: URL',
          ].join('\n'));

      // 받은 순서 · 메모 빼기
      final received = LedgerText.build(package,
              order: LedgerOrder.received, includeMemo: false)
          .single;
      expect(received, contains('1. 강민호'));
      expect(received, contains('2. 강지은 · 50,000원 · 신부측 · 계좌 · 식권 2\n'));
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
      final back = LedgerText.parse(text)!.toPackage();
      expect(back.entries.single.name, '김-철수');
      expect(back.entries.single.memo, '회사 - 동기 둘째 줄');
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

  group('붙여넣어 읽기', () {
    test('왕복: 만든 글을 다시 읽으면 같은 데이터 (가나다 · 받은 순서 모두)', () {
      final package = bigPackage(40);
      for (final order in LedgerOrder.values) {
        final parsed = LedgerText.parse(
            LedgerText.build(package, order: order).single)!;
        expect(parsed.unreadable, 0);
        expect(parsed.title, '누나 결혼식');
        expect(parsed.date, DateTime(2026, 12, 26));
        expect(parsed.operatorName, '송희강');
        final back = parsed.toPackage();
        expect(back.reception.sides, ['신랑측', '신부측']);
        expect(back.reception.methodEnabled, isTrue);
        expect(back.reception.mealTicketEnabled, isTrue);
        expect(back.reception.eventType, '결혼');
        expect(rows(back), rows(package));
        expect(back.totals.amount, package.totals.amount);
        expect(back.totals.mealTickets, package.totals.mealTickets);
      }
    });

    test('나눠 보낸 메시지를 모두 읽으면 전체 명단과 같다', () {
      final package = bigPackage(250);
      final back = [
        for (final text in LedgerText.build(package))
          ...LedgerText.parse(text)!.toPackage().entries,
      ];
      expect(back.length, 250);
      expect(rows(ReceptionPackage(package.reception, back)), rows(package));
    });

    test('사람이 고친 줄은 건너뛰고 몇 줄인지 알려준다', () {
      final edited = LedgerText.build(bigPackage(5))
          .single
          .replaceFirst('\n2. ', '\n2. 이건 이상한 줄\n');
      final text = '$edited\n감사합니다!\n7. 금액없음 · 모름';
      final parsed = LedgerText.parse(text)!;
      expect(parsed.count, 4);
      // '2. 이건 이상한 줄', 원래 2번 줄의 나머지(번호 없는 줄), '감사합니다!', '7. 금액없음 · 모름'
      expect(parsed.unreadable, 4);
    });

    test('이 앱이 만든 글이 아니면 null', () {
      expect(LedgerText.parse('안녕하세요\n내일 봬요'), isNull);
      expect(LedgerText.parse(''), isNull);
    });
  });

  group('붙여넣어 가져오기 (DB)', () {
    late Directory dir;
    late DatabaseHelper helper;
    late Repository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('gyeongjosa_text');
      helper = DatabaseHelper.forTest(p.join(dir.path, 'test.db'));
      repo = Repository(helper);
    });

    tearDown(() async {
      await helper.close();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('120명을 두 메시지로: 하나의 내 행사로 합쳐지고, 다시 붙여도 중복 없음', () async {
      final parts = LedgerText.build(bigPackage(120));
      expect(parts.length, 2);
      final first = LedgerText.parse(parts[0])!;
      final r1 = await repo.applyImport(first.toPackage(),
          newEvent: first.newEvent());
      expect(r1.plan.items.length, 100);

      final second = LedgerText.parse(parts[1])!;
      final r2 =
          await repo.applyImport(second.toPackage(), eventId: r1.eventId);
      expect(r2.plan.items.length, 20);
      expect(await repo.countMyEvents(), 1);
      expect((await repo.recordsForEvent(r1.eventId)).length, 120);
      expect(await repo.countPeople(), 120);

      // 같은 메시지를 또 붙여도 그대로
      final again =
          await repo.applyImport(first.toPackage(), eventId: r1.eventId);
      expect(again.plan.items, isEmpty);
      expect(again.plan.alreadyImported, 100);
      expect((await repo.recordsForEvent(r1.eventId)).length, 120);

      // 구분 · 식권 · 방법이 기록에 들어간다 (통계 · 엑셀에 그대로 나옴)
      final records = await repo.recordsForEvent(r1.eventId);
      expect(records.every((r) => r.direction == '받음'), isTrue);
      expect(records.where((r) => r.side == '신랑측').length, 60);
      expect((await repo.yearTotals(2026)).receivedCount, 120);
    });

    test('무료: 50명까지만 새 사람으로 가져오고, 나머지는 나중에 같은 메시지로', () async {
      final text = LedgerText.build(bigPackage(100)).single;
      final parsed = LedgerText.parse(text)!;
      final plan = await repo.planImport(parsed.toPackage(),
          maxPeople: FreeLimits.people);
      expect(FreeLimits.people, 50);
      expect(plan.items.length, 50);
      expect(plan.skippedByLimit, 50);

      final limited = await repo.applyImport(parsed.toPackage(),
          newEvent: parsed.newEvent(), maxPeople: FreeLimits.people);
      expect(await repo.countPeople(), 50);
      final rest = await repo.applyImport(parsed.toPackage(),
          eventId: limited.eventId);
      expect(rest.plan.items.length, 50);
      expect(await repo.countPeople(), 100);
    });
  });
}
