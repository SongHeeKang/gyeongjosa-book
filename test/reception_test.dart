import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/event.dart';
import 'package:gyeongjosa/models/person.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/services/backup_service.dart';
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

  setUpAll(() => initializeDateFormatting('ko_KR'));

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
      expect(second.plan.items.where((i) => i.needsReview).length, 1);

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

  // 추가 Q: DB 7버전(내 행사별 받기 설정)과 예전 파일 호환
  group('DB 7버전과 예전 파일', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('gyeongjosa_v7');
    });

    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException catch (_) {}
    });

    /// 지금 출시된 앱(DB 6버전)이 만드는 것과 같은 구조의 DB 파일
    Future<String> makeV6(String name) async {
      final path = p.join(dir.path, name);
      final db = await openDatabase(path, version: 6, onCreate: (db, _) async {
        await db.execute(
            "CREATE TABLE people (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, relation TEXT NOT NULL DEFAULT '기타', phone TEXT, memo TEXT, created_at TEXT NOT NULL)");
        await db.execute(
            "CREATE TABLE events (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL DEFAULT '기타', title TEXT NOT NULL, date TEXT NOT NULL, is_mine INTEGER NOT NULL DEFAULT 0, place TEXT, memo TEXT, notify INTEGER NOT NULL DEFAULT 1, person_id INTEGER REFERENCES people(id) ON DELETE SET NULL, pending_hidden INTEGER NOT NULL DEFAULT 0)");
        await db.execute(
            "CREATE TABLE records (id INTEGER PRIMARY KEY AUTOINCREMENT, person_id INTEGER NOT NULL REFERENCES people(id) ON DELETE CASCADE, event_id INTEGER REFERENCES events(id) ON DELETE SET NULL, direction TEXT NOT NULL, amount INTEGER NOT NULL, method TEXT NOT NULL DEFAULT '현금', date TEXT NOT NULL, memo TEXT, event_type TEXT, needs_review INTEGER NOT NULL DEFAULT 0, side TEXT, meal_tickets INTEGER)");
        await db.execute(
            "CREATE TABLE receptions (id TEXT PRIMARY KEY, title TEXT NOT NULL, event_type TEXT NOT NULL DEFAULT '기타', date TEXT NOT NULL, sides TEXT NOT NULL, operator_name TEXT NOT NULL DEFAULT '', started_at TEXT NOT NULL, finished_at TEXT, imported INTEGER NOT NULL DEFAULT 0, meal_ticket_enabled INTEGER NOT NULL DEFAULT 1, default_meal_tickets INTEGER NOT NULL DEFAULT 1, method_enabled INTEGER NOT NULL DEFAULT 1)");
        await db.execute(
            "CREATE TABLE reception_entries (id TEXT PRIMARY KEY, reception_id TEXT NOT NULL REFERENCES receptions(id) ON DELETE CASCADE, name TEXT NOT NULL, amount INTEGER NOT NULL, side TEXT NOT NULL DEFAULT '', method TEXT NOT NULL DEFAULT '현금', meal_tickets INTEGER NOT NULL DEFAULT 1, memo TEXT, created_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)");
        await db.execute(
            'CREATE TABLE imported_entries (entry_id TEXT PRIMARY KEY, imported_at TEXT NOT NULL)');
        await db.insert('people', {'name': '옛손님', 'created_at': '2026-01-01'});
        await db.insert('events', {
          'title': '우리 결혼식',
          'date': '2026-10-03',
          'is_mine': 1,
          'type': '결혼'
        });
        await db.insert('events',
            {'title': '친구 결혼식', 'date': '2026-12-01', 'is_mine': 0});
        await db.insert('records', {
          'person_id': 1,
          'event_id': 1,
          'direction': '받음',
          'amount': 50000,
          'date': '2026-10-03'
        });
        await db.insert('receptions', {
          'id': 'old-r',
          'title': '누나 결혼식',
          'date': '2026-09-01',
          'sides': '["신부측"]',
          'started_at': '2026-09-01T10:00:00',
        });
        await db.insert('reception_entries', {
          'id': 'old-e',
          'reception_id': 'old-r',
          'name': '대신손님',
          'amount': 30000,
          'side': '신부측',
          'created_at': '2026-09-01T10:05:00',
        });
      });
      await db.close();
      return path;
    }

    test('v6 → v7: 기록은 그대로, 예전 내 행사는 식권 · 계좌 끔으로 설정을 다시 묻지 않는다',
        () async {
      final helper = DatabaseHelper.forTest(await makeV6('old.db'));
      final repo = Repository(helper);
      final mine = (await repo.myEvents()).single;
      expect(mine.receiveSettingsDone, isTrue);
      expect(mine.sides, ['전체']);
      expect(mine.mealTicketEnabled, isFalse);
      expect(mine.methodEnabled, isFalse);
      final others = (await repo.allEvents()).where((e) => !e.isMine);
      expect(others.single.receiveSettingsDone, isFalse);
      expect((await repo.allRecords()).single.amount, 50000);
      expect((await repo.getReceptionPackage('old-r'))!.entries.single.name,
          '대신손님');
      await helper.close();
    });

    test('예전(v6) 백업 파일은 검사를 통과하고 복원하면 v8로 올라간다', () async {
      final backup = await makeV6('backup.db');
      await DatabaseHelper.validateBackupFile(backup);

      final helper = DatabaseHelper.forTest(p.join(dir.path, 'app.db'));
      await Repository(helper).insertPerson(
          Person(name: '지금사람', createdAt: DateTime(2026)));
      await BackupService(helper).restoreFrom(backup);
      final repo = Repository(helper);
      expect((await repo.allPeople()).single.name, '옛손님');
      expect((await repo.myEvents()).single.receiveSettingsDone, isTrue);
      final db = await helper.database;
      expect((await db.rawQuery('PRAGMA user_version')).first.values.first, 8);
      await helper.close();
    });

    test('새 내 행사는 처음 받을 때 설정을 묻고, 행사 이름을 고쳐도 설정은 남는다', () async {
      final helper = DatabaseHelper.forTest(p.join(dir.path, 'new.db'));
      final repo = Repository(helper);
      final id = await repo.insertEvent(myEvent());
      expect((await repo.getEvent(id))!.receiveSettingsDone, isFalse);

      await repo.updateEventReceiveSettings((await repo.getEvent(id))!
          .withReceiveSettings(
              sides: const ['신랑측', '신부측'],
              mealTicketEnabled: true,
              defaultMealTickets: 2,
              methodEnabled: true));
      await repo.updateEvent(Event(
          id: id,
          type: '결혼',
          title: '이름 고침',
          date: DateTime(2026, 11, 1),
          isMine: true));
      final e = (await repo.getEvent(id))!;
      expect(e.title, '이름 고침');
      expect(e.sides, ['신랑측', '신부측']);
      expect(e.mealTicketEnabled, isTrue);
      expect(e.defaultMealTickets, 2);
      expect(e.methodEnabled, isTrue);
      await helper.close();
    });

    test('내 행사로 바꾸기: 구분 · 식권이 기록에, 받기 설정이 새 내 행사에 옮겨지고 원래 장부는 지워진다', () async {
      final helper = DatabaseHelper.forTest(p.join(dir.path, 'move.db'));
      final repo = Repository(helper);
      final r = Reception(
        id: 'r1',
        title: '누나 결혼식',
        eventType: '결혼',
        date: DateTime(2026, 12, 26),
        sides: const ['신랑측', '신부측'],
        operatorName: '송희강',
        startedAt: DateTime(2026, 12, 26, 9),
        mealTicketEnabled: true,
        defaultMealTickets: 2,
        methodEnabled: true,
      );
      await repo.insertReception(r);
      final package = ReceptionPackage(r, [
        ReceptionEntry(
            id: 'x',
            receptionId: 'r1',
            name: '박지원',
            amount: 100000,
            side: '신부측',
            method: '계좌',
            mealTickets: 3,
            createdAt: DateTime(2026, 12, 26, 10)),
      ]);
      // 내 행사로 옮기기의 '새로 만들기'와 같은 새 행사 (화면의 _newEvent와 같은 값)
      final result = await repo.applyImport(package,
          newEvent: Event(
            type: r.eventType,
            title: r.title,
            date: r.date,
            isMine: true,
            reminderDays: null,
            receiveSides: r.sides,
            mealTicketEnabled: r.mealTicketEnabled,
            defaultMealTickets: r.defaultMealTickets,
            methodEnabled: r.methodEnabled,
          ),
          removeReception: true);
      final record = (await repo.recordsForEvent(result.eventId)).single;
      expect(record.side, '신부측');
      expect(record.mealTickets, 3);
      expect(record.method, '계좌');
      final event = (await repo.getEvent(result.eventId))!;
      expect(event.sides, ['신랑측', '신부측']);
      expect(event.mealTicketEnabled, isTrue);
      expect(event.defaultMealTickets, 2);
      // 대신 받은 명단은 사람 목록과 따로이고, 옮긴 뒤에만 사람이 생긴다
      expect(await repo.countPeople(), 1);
      // 바꾼 뒤에는 다른 사람 행사 목록에서 빠진다
      expect(await repo.getReceptionPackage('r1'), isNull);
      await helper.close();
    });

  });
}
