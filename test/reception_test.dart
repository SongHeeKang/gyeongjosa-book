import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/event.dart';
import 'package:gyeongjosa/models/person.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/services/reception_file_service.dart';
import 'package:gyeongjosa/services/reception_import.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ReceptionEntry entry(String id, String name,
        {int amount = 50000, String receptionId = 'r1'}) =>
    ReceptionEntry(
      id: id,
      receptionId: receptionId,
      name: name,
      amount: amount,
      side: '신랑측',
      createdAt: DateTime(2026, 11, 1, 10).add(Duration(seconds: id.hashCode % 100)),
    );

Reception reception({String id = 'r1', String title = '홍길동 결혼식'}) => Reception(
      id: id,
      title: title,
      eventType: '결혼',
      date: DateTime(2026, 11, 1),
      sides: const ['신랑측', '신부측'],
      operatorName: '김민수',
      startedAt: DateTime(2026, 11, 1, 9),
    );

Event myEvent() => Event(
    type: '결혼', title: '홍길동 결혼식', date: DateTime(2026, 11, 1), isMine: true);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('요약 메시지', () {
    setUpAll(() => initializeDateFormatting('ko_KR'));

    test('식권 기록을 끄면 식권이 없고, 현금만이면 합계도 나누지 않는다', () {
      final package = ReceptionPackage(
        Reception(
          id: 'r9',
          title: '돌잔치',
          eventType: '돌',
          date: DateTime(2026, 11, 1),
          sides: const ['전체'],
          operatorName: '',
          startedAt: DateTime(2026, 11, 1),
          mealTicketEnabled: false,
          methodEnabled: false,
        ),
        [
          ReceptionEntry(
            id: 'e',
            receptionId: 'r9',
            name: '김철수',
            amount: 50000,
            side: '전체',
            mealTickets: 0,
            createdAt: DateTime(2026, 11, 1),
          ),
        ],
      );
      final text = ReceptionFileService.summaryMessage(package);
      expect(text, isNot(contains('식권')));
      expect(text, isNot(contains('계좌이체')));
      expect(package.entries.single.recordMemo, isNot(contains('식권')));

      // 파일로 보내고 받아도 설정이 유지된다
      final parsed = ReceptionPackage.parse(package.toJsonString());
      expect(parsed.reception.mealTicketEnabled, isFalse);
      expect(parsed.reception.methodEnabled, isFalse);
    });

    test('계좌이체를 구분하면 요약에 현금 · 계좌 합계가 나온다', () {
      final package = ReceptionPackage(
        Reception(
          id: 'r9',
          title: '돌잔치',
          eventType: '돌',
          date: DateTime(2026, 11, 1),
          sides: const ['전체'],
          operatorName: '',
          startedAt: DateTime(2026, 11, 1),
        ),
        [
          ReceptionEntry(
            id: 'a',
            receptionId: 'r9',
            name: '김철수',
            amount: 50000,
            side: '전체',
            createdAt: DateTime(2026, 11, 1),
          ),
          ReceptionEntry(
            id: 'b',
            receptionId: 'r9',
            name: '이영희',
            amount: 100000,
            side: '전체',
            method: '계좌',
            createdAt: DateTime(2026, 11, 1),
          ),
        ],
      );
      expect(ReceptionFileService.summaryMessage(package),
          contains('현금 50,000원 · 계좌이체 100,000원'));
    });

    test('총액 · 구분별 소계 · 식권 · 앱 링크가 있고 전체 명단은 없다', () {
      final text = ReceptionFileService.summaryMessage(ReceptionPackage(
        reception(),
        [
          entry('a', '김철수', amount: 100000),
          ReceptionEntry(
              id: 'b',
              receptionId: 'r1',
              name: '이영희',
              amount: 50000,
              side: '신부측',
              mealTickets: 2,
              createdAt: DateTime(2026, 11, 1)),
        ],
      ));
      expect(text, contains('[경조사 장부] 홍길동 결혼식 접수 결과'));
      expect(text, contains('2026년 11월 1일 (일) · 접수: 김민수'));
      expect(text, contains('총 2명 · 150,000원'));
      expect(text, contains('- 신랑측 1명 · 100,000원'));
      expect(text, contains('- 신부측 1명 · 50,000원'));
      expect(text, contains('식권 3장'));
      expect(text,
          contains('https://play.google.com/store/apps/details?id=com.heekangsong.gyeongjosa'));
      expect(text, isNot(contains('김철수')));
      // 받는 사람 안내 (추가 O)
      expect(text, contains('[장부 파일 받는 방법]'));
      expect(text, contains("② 함께 보낸 장부 파일(.json)을 눌러 '경조사 장부'로 열기"));
      expect(text, contains('※ 무료는 30명까지 가져올 수 있어요(이 장부 2명)'));
      expect(text, contains('※ 카카오톡 파일은 보관 기간이 지나면 받을 수 없어요'));
      expect(text, isNot(contains('전체 명단은')));
      // 첫 줄 제목은 한 번만
      expect('접수 결과'.allMatches(text).length, 1);
      expect(text, isNot(contains('이영희')));
    });
  });

  group('파일 형식', () {
    test('보내고 읽으면 내용이 같고, 지운 항목은 빠진다', () {
      final text = ReceptionPackage(reception(), [
        entry('a', '김철수', amount: 100000),
        ReceptionEntry(
            id: 'b',
            receptionId: 'r1',
            name: '지운사람',
            amount: 1000,
            side: '',
            createdAt: DateTime(2026),
            deleted: true),
      ]).toJsonString();
      final parsed = ReceptionPackage.parse(text);
      expect(parsed.reception.title, '홍길동 결혼식');
      expect(parsed.reception.sides, ['신랑측', '신부측']);
      expect(parsed.entries.single.name, '김철수');
      expect(parsed.entries.single.amount, 100000);
    });

    test('다른 파일 · 손상된 파일 · 새 버전 파일은 안내 문구와 함께 거절', () {
      for (final bad in [
        'not json',
        '{}',
        '{"format":"other","version":1}',
        '{"format":"gyeongjosa_reception","version":1,"reception":{},"entries":[]}',
        '{"format":"gyeongjosa_reception","version":99}',
        '{"format":"gyeongjosa_reception","version":1,"reception":{"id":"r","title":"t","date":"2026-01-01"},"entries":[{"id":"a","name":"","amount":1}]}',
        '{"format":"gyeongjosa_reception","version":1,"reception":{"id":"r","title":"t","date":"2026-01-01"},"entries":[{"id":"a","name":"x","amount":-5}]}',
      ]) {
        expect(() => ReceptionPackage.parse(bad), throwsFormatException,
            reason: bad);
      }
    });

    test('파일 이름 규칙: 경조사장부_행사이름_날짜_접수자.json', () {
      expect(ReceptionFileService.fileName(reception(title: '홍길동/김영희 결혼식')),
          '경조사장부_홍길동_김영희_결혼식_2026-11-01_김민수.json');
    });
  });

  group('가져오기 규칙', () {
    test('한도를 넘는 새 사람은 남기고, 기존 사람은 한도와 상관없이 가져온다', () {
      final plan = buildImportPlan(
        entries: [entry('a', '새1'), entry('b', '새2'), entry('c', '기존')],
        importedIds: const {},
        peopleByName: const {
          '기존': [7]
        },
        namesInEvent: const {},
        newPersonSlots: 1,
      );
      expect(plan.items.length, 2);
      expect(plan.skippedByLimit, 1);
      expect(plan.remaining, 3);
      expect(plan.items.where((i) => i.personId == 7).length, 1);
    });

    test('같은 이름이 여러 명이거나 파일 안에 겹치면 확인 필요', () {
      final plan = buildImportPlan(
        entries: [
          entry('a', '여럿'),
          ReceptionEntry(
              id: 'b',
              receptionId: 'r1',
              name: '겹침',
              amount: 1,
              side: '',
              createdAt: DateTime(2026, 1, 1)),
          ReceptionEntry(
              id: 'c',
              receptionId: 'r1',
              name: '겹침',
              amount: 1,
              side: '',
              createdAt: DateTime(2026, 1, 2)),
        ],
        importedIds: const {},
        peopleByName: const {
          '여럿': [1, 2]
        },
        namesInEvent: const {},
      );
      final byId = {for (final i in plan.items) i.entry.id: i};
      expect(byId['a']!.needsReview, isTrue);
      expect(byId['b']!.needsReview, isFalse);
      expect(byId['c']!.needsReview, isTrue);
    });
  });

  group('DB', () {
    late Directory dir;
    late DatabaseHelper helper;
    late Repository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('gyeongjosa_test');
      helper = DatabaseHelper.forTest(p.join(dir.path, 'test.db'));
      repo = Repository(helper);
    });

    tearDown(() async {
      await helper.close();
      await dir.delete(recursive: true);
    });

    test('v2 → v3 업그레이드에서 기존 데이터가 유지된다', () async {
      final path = p.join(dir.path, 'old.db');
      final old = await openDatabase(path, version: 2, onCreate: (db, _) async {
        await db.execute(
            "CREATE TABLE people (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, relation TEXT NOT NULL DEFAULT '기타', phone TEXT, memo TEXT, created_at TEXT NOT NULL)");
        await db.execute(
            "CREATE TABLE events (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL DEFAULT '기타', title TEXT NOT NULL, date TEXT NOT NULL, is_mine INTEGER NOT NULL DEFAULT 0, place TEXT, memo TEXT, notify INTEGER NOT NULL DEFAULT 1)");
        await db.execute(
            "CREATE TABLE records (id INTEGER PRIMARY KEY AUTOINCREMENT, person_id INTEGER NOT NULL REFERENCES people(id) ON DELETE CASCADE, event_id INTEGER REFERENCES events(id) ON DELETE SET NULL, direction TEXT NOT NULL, amount INTEGER NOT NULL, method TEXT NOT NULL DEFAULT '현금', date TEXT NOT NULL, memo TEXT, event_type TEXT)");
        await db.insert('people', {'name': '옛사람', 'created_at': '2026-01-01'});
        await db.insert('records', {
          'person_id': 1,
          'direction': '보냄',
          'amount': 50000,
          'date': '2026-01-01'
        });
      });
      await old.close();

      final upgraded = DatabaseHelper.forTest(path);
      final oldRepo = Repository(upgraded);
      expect((await oldRepo.allPeople()).single.name, '옛사람');
      final record = (await oldRepo.allRecords()).single;
      expect(record.amount, 50000);
      expect(record.needsReview, isFalse);
      expect(await oldRepo.receptionSummaries(), isEmpty);
      await upgraded.close();
    });

    test('접수 명단은 사람 목록에 섞이지 않고, 되돌린 항목은 합계에서 빠진다', () async {
      await repo.insertReception(reception());
      await repo.insertReceptionEntry(entry('a', '손님1'));
      await repo.insertReceptionEntry(entry('b', '손님2', amount: 100000));
      await repo.deleteReceptionEntry('a');

      expect(await repo.countPeople(), 0);
      final package = (await repo.getReceptionPackage('r1'))!;
      expect(package.totals.count, 1);
      expect(package.totals.amount, 100000);
      expect((await repo.receptionSummaries()).single.total, 100000);
    });

    test('같은 파일을 두 번 가져와도 중복 저장되지 않고, 지운 내역도 되살아나지 않는다', () async {
      final package =
          ReceptionPackage(reception(), [entry('a', '김철수'), entry('b', '이영희')]);
      final first = await repo.applyImport(package, newEvent: myEvent());
      expect(first.plan.items.length, 2);
      expect(await repo.countRecords(), 2);

      final again = await repo.applyImport(package, eventId: first.eventId);
      expect(again.plan.items, isEmpty);
      expect(again.plan.alreadyImported, 2);
      expect(await repo.countRecords(), 2);

      final record = (await repo.allRecords()).first;
      await repo.deleteRecord(record.id!);
      await repo.applyImport(package, eventId: first.eventId);
      expect(await repo.countRecords(), 1);
    });

    test('폰 2대의 파일이 같은 장부에 합쳐지고, 같은 이름은 확인 필요로 표시된다', () async {
      final phone1 = ReceptionPackage(reception(id: 'p1'),
          [entry('a', '김철수', receptionId: 'p1')]);
      final phone2 = ReceptionPackage(reception(id: 'p2'), [
        entry('b', '김철수', receptionId: 'p2'),
        entry('c', '이영희', receptionId: 'p2'),
      ]);
      final first = await repo.applyImport(phone1, newEvent: myEvent());
      final second = await repo.applyImport(phone2, eventId: first.eventId);
      expect(second.plan.reviewCount, 1);

      final records = await repo.recordsForEvent(first.eventId);
      expect(records.length, 3);
      expect(records.every((r) => r.direction == '받음'), isTrue);
      expect(await repo.countPeople(), 2);
      expect(await repo.countMyEvents(), 1);

      // 다른 사람으로 분리하면 사람이 늘고 표시가 사라진다
      final flagged = records.firstWhere((r) => r.needsReview);
      await repo.moveRecordToNewPerson(flagged.id!, flagged.personName!);
      expect(await repo.countPeople(), 3);
      expect((await repo.recordsForEvent(first.eventId))
          .where((r) => r.needsReview), isEmpty);
    });

    test('한도로 남은 항목은 나중에 같은 파일로 마저 가져올 수 있다', () async {
      for (var i = 0; i < 29; i++) {
        await repo.insertPerson(Person(name: '기존$i', createdAt: DateTime(2026)));
      }
      await repo.insertReception(reception());
      final package = ReceptionPackage(
          reception(), [entry('a', '새1'), entry('b', '새2'), entry('c', '새3')]);

      final limited = await repo.applyImport(package,
          newEvent: myEvent(), maxPeople: 30);
      expect(limited.plan.items.length, 1);
      expect(limited.plan.skippedByLimit, 2);
      expect(await repo.countPeople(), 30);
      expect((await repo.getReceptionPackage('r1'))!.reception.imported, isFalse);

      final all = await repo.applyImport(package, eventId: limited.eventId);
      expect(all.plan.items.length, 2);
      expect(all.plan.alreadyImported, 1);
      expect(await repo.countPeople(), 32);
      expect((await repo.getReceptionPackage('r1'))!.reception.imported, isTrue);
    });
  });
}
