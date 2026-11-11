// 추가 L: CSV 내보내기를 행사별로, 받은 기록에 구분 · 식권 저장
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/event.dart';
import 'package:gyeongjosa/models/gift_record.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/services/csv_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

GiftRecord _rec(int id, String name, String relation, int amount,
        {int? eventId,
        String direction = '받음',
        String? side,
        String method = '현금',
        int? meals,
        String? memo,
        String date = '2026-10-11'}) =>
    GiftRecord(
      id: id,
      personId: id,
      eventId: eventId,
      direction: direction,
      amount: amount,
      method: method,
      date: DateTime.parse(date),
      memo: memo,
      side: side,
      mealTickets: meals,
      personName: name,
      personRelation: relation,
    );

/// CSV를 줄 목록으로 (BOM과 줄 끝 문자를 뗀다)
List<String> _lines(String csv) =>
    csv.replaceFirst('﻿', '').split(RegExp(r'\r?\n'));

void main() {
  test('기획서 예시대로 행사마다 제목 · 열 제목 · 가나다순 손님 · 합계 · 소계', () {
    final csv = CsvService.buildCsv(
      today: DateTime(2026, 11, 11),
      events: [
        Event(id: 1, type: '결혼', title: '우리 결혼식', date: DateTime(2026, 10, 11), isMine: true),
        Event(id: 2, type: '결혼', title: '김민수 결혼식', date: DateTime(2026, 11, 1), isMine: false),
      ],
      records: [
        _rec(2, '강지은', '회사', 50000,
            eventId: 1, side: '신부측', method: '계좌', meals: 2, memo: '회사 동료'),
        _rec(1, '강민호', '친구', 100000, eventId: 1, side: '신랑측', meals: 1),
        _rec(3, '김민수', '회사', 100000,
            eventId: 2, direction: '보냄', method: '계좌', date: '2026-11-01'),
      ],
    );
    expect(_lines(csv), [
      '경조사 장부 내보내기,2026-11-11',
      '',
      '[행사] 김민수 결혼식,2026-11-01,결혼,보냄',
      '번호,이름,관계,구분,금액,결제 방법,식권,메모,날짜',
      '1,김민수,회사,,100000,계좌,,,2026-11-01',
      '합계,1명,,,100000,,,,',
      '',
      '[행사] 우리 결혼식,2026-10-11,결혼,받음',
      '번호,이름,관계,구분,금액,결제 방법,식권,메모,날짜',
      '1,강민호,친구,신랑측,100000,현금,1,,2026-10-11',
      '2,강지은,회사,신부측,50000,계좌,2,회사 동료,2026-10-11',
      '합계,2명,,,150000,,3,,',
      '신랑측 소계,1명,,,100000,,1,,',
      '신부측 소계,1명,,,50000,,2,,',
      '현금 합계,,,,100000,,,,',
      '계좌 합계,,,,50000,,,,',
      '',
      '[전체 합계],보냄 1건 100000,받음 2건 150000',
    ]);
  });

  test('행사 없이 기록한 내역은 맨 아래, 옮기지 않은 접수 장부도 들어간다', () {
    final reception = Reception(
      id: 'r1',
      title: '홍길동 결혼식',
      eventType: '결혼',
      date: DateTime(2026, 11, 15),
      sides: const ['신랑측'],
      operatorName: '박지원',
      startedAt: DateTime(2026, 11, 15),
    );
    final csv = CsvService.buildCsv(
      today: DateTime(2026, 11, 11),
      events: const [],
      records: [_rec(1, '이서연', '지인', 30000, direction: '보냄', date: '2026-03-01')],
      receptions: [
        ReceptionPackage(reception, [
          ReceptionEntry(
              id: 'e1',
              receptionId: 'r1',
              name: '최유나',
              amount: 50000,
              side: '신랑측',
              mealTickets: 2,
              createdAt: DateTime(2026, 11, 15, 12)),
        ]),
      ],
    );
    final lines = _lines(csv);
    expect(lines, containsAllInOrder([
      '[접수 장부] 홍길동 결혼식,2026-11-15,결혼,받음',
      '1,최유나,,신랑측,50000,현금,2,,2026-11-15',
      '[행사 없이 기록한 내역],,,보냄',
      '1,이서연,지인,,30000,현금,,,2026-03-01',
      '[전체 합계],보냄 1건 30000,받음 0건 0',
    ]));
  });

  group('받은 기록의 구분 · 식권', () {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('csv_export_test'));
    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('접수 장부를 가져오면 구분 · 식권을 따로 저장하고 메모에는 섞지 않는다', () async {
      final helper = DatabaseHelper.forTest(p.join(dir.path, 'a.db'));
      final repo = Repository(helper);
      final reception = Reception(
        id: 'r1',
        title: '홍길동 결혼식',
        eventType: '결혼',
        date: DateTime(2026, 11, 15),
        sides: const ['신랑측', '신부측'],
        operatorName: '',
        startedAt: DateTime(2026, 11, 15),
      );
      await repo.applyImport(
        ReceptionPackage(reception, [
          ReceptionEntry(
              id: 'e1',
              receptionId: 'r1',
              name: '강지은',
              amount: 50000,
              side: '신부측',
              mealTickets: 2,
              memo: '회사 동료',
              createdAt: DateTime(2026, 11, 15)),
        ]),
        newEvent: Event(type: '결혼', title: '우리', date: DateTime(2026, 11, 15), isMine: true),
      );
      final record = (await repo.allRecords()).single;
      expect(record.side, '신부측');
      expect(record.mealTickets, 2);
      expect(record.memo, '회사 동료');
      await helper.close();
    });

    test('v5 → v6: 이미 가져온 기록은 남아 있는 접수 장부에서 구분 · 식권을 채우고, 나머지는 그대로', () async {
      final path = p.join(dir.path, 'old.db');
      final old = await openDatabase(path, version: 5, onCreate: (db, _) async {
        await db.execute(
            "CREATE TABLE people (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, relation TEXT NOT NULL DEFAULT '기타', phone TEXT, memo TEXT, created_at TEXT NOT NULL)");
        await db.execute(
            "CREATE TABLE events (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL DEFAULT '기타', title TEXT NOT NULL, date TEXT NOT NULL, is_mine INTEGER NOT NULL DEFAULT 0, place TEXT, memo TEXT, notify INTEGER NOT NULL DEFAULT 1, person_id INTEGER, pending_hidden INTEGER NOT NULL DEFAULT 0)");
        await db.execute(
            "CREATE TABLE records (id INTEGER PRIMARY KEY AUTOINCREMENT, person_id INTEGER NOT NULL, event_id INTEGER, direction TEXT NOT NULL, amount INTEGER NOT NULL, method TEXT NOT NULL DEFAULT '현금', date TEXT NOT NULL, memo TEXT, event_type TEXT, needs_review INTEGER NOT NULL DEFAULT 0)");
        await db.execute(
            "CREATE TABLE receptions (id TEXT PRIMARY KEY, title TEXT NOT NULL, event_type TEXT NOT NULL DEFAULT '기타', date TEXT NOT NULL, sides TEXT NOT NULL, operator_name TEXT NOT NULL DEFAULT '', started_at TEXT NOT NULL, finished_at TEXT, imported INTEGER NOT NULL DEFAULT 0, meal_ticket_enabled INTEGER NOT NULL DEFAULT 1, default_meal_tickets INTEGER NOT NULL DEFAULT 1, method_enabled INTEGER NOT NULL DEFAULT 1)");
        await db.execute(
            "CREATE TABLE reception_entries (id TEXT PRIMARY KEY, reception_id TEXT NOT NULL, name TEXT NOT NULL, amount INTEGER NOT NULL, side TEXT NOT NULL DEFAULT '', method TEXT NOT NULL DEFAULT '현금', meal_tickets INTEGER NOT NULL DEFAULT 1, memo TEXT, created_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)");
        await db.execute(
            'CREATE TABLE imported_entries (entry_id TEXT PRIMARY KEY, imported_at TEXT NOT NULL)');
        for (final name in ['강지은', '직접입력', '메모고침']) {
          await db.insert('people', {'name': name, 'created_at': '2026-01-01'});
        }
        // 1) 가져온 기록: 예전 방식대로 메모에 구분 · 식권이 섞여 있음
        await db.insert('records', {
          'person_id': 1, 'direction': '받음', 'amount': 50000,
          'date': '2026-11-15', 'memo': '신부측 · 식권 2매 · 회사 동료',
        });
        // 2) 직접 입력한 기록: 그대로 둔다
        await db.insert('records', {
          'person_id': 2, 'direction': '받음', 'amount': 30000,
          'date': '2026-11-15', 'memo': '신부측',
        });
        // 3) 가져온 뒤 사용자가 메모를 고친 기록: 그대로 둔다
        await db.insert('records', {
          'person_id': 3, 'direction': '받음', 'amount': 70000,
          'date': '2026-11-15', 'memo': '내가 고친 메모',
        });
        await db.insert('reception_entries', {
          'id': 'e1', 'reception_id': 'r1', 'name': '강지은', 'amount': 50000,
          'side': '신부측', 'meal_tickets': 2, 'memo': '회사 동료', 'created_at': '2026-11-15',
        });
        await db.insert('reception_entries', {
          'id': 'e3', 'reception_id': 'r1', 'name': '메모고침', 'amount': 70000,
          'side': '신랑측', 'meal_tickets': 1, 'created_at': '2026-11-15',
        });
        await db.insert('imported_entries', {'entry_id': 'e1', 'imported_at': '2026-11-16'});
        await db.insert('imported_entries', {'entry_id': 'e3', 'imported_at': '2026-11-16'});
      });
      await old.close();

      final helper = DatabaseHelper.forTest(path);
      final records = await Repository(helper).allRecords();
      GiftRecord of(String name) => records.firstWhere((r) => r.personName == name);
      expect(of('강지은').side, '신부측');
      expect(of('강지은').mealTickets, 2);
      expect(of('강지은').memo, '회사 동료');
      expect(of('직접입력').side, isNull);
      expect(of('직접입력').memo, '신부측');
      expect(of('메모고침').side, isNull);
      expect(of('메모고침').memo, '내가 고친 메모');
      expect(records.length, 3);
      await helper.close();
    });
  });
}
