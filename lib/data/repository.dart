import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/constants.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../models/person.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../services/reception_import.dart';
import 'database_helper.dart';

/// 화면에서 쓰는 모든 DB 읽기/쓰기를 모아둔 곳.
class Repository {
  Repository(this._helper);
  final DatabaseHelper _helper;

  Future<Database> get _db => _helper.database;

  static const _recordSelect = '''
    SELECT r.*, p.name AS person_name, p.relation AS person_relation,
           e.title AS event_title, e.type AS ev_type
    FROM records r
    JOIN people p ON p.id = r.person_id
    LEFT JOIN events e ON e.id = r.event_id
  ''';

  // ───────────────────────── 사람 ─────────────────────────

  Future<int> countPeople() async {
    final db = await _db;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM people')) ?? 0;
  }

  Future<List<PersonSummary>> peopleSummaries() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT p.*,
        COALESCE(SUM(CASE WHEN r.direction = '보냄' THEN r.amount END), 0) AS sent_total,
        COALESCE(SUM(CASE WHEN r.direction = '받음' THEN r.amount END), 0) AS received_total
      FROM people p
      LEFT JOIN records r ON r.person_id = p.id
      GROUP BY p.id
      ORDER BY p.name, p.id
    ''');
    return rows
        .map((r) => PersonSummary(
              person: Person.fromMap(r),
              sentTotal: r['sent_total'] as int? ?? 0,
              receivedTotal: r['received_total'] as int? ?? 0,
            ))
        .toList();
  }

  Future<List<Person>> allPeople() async {
    final db = await _db;
    final rows = await db.query('people', orderBy: 'name, id');
    return rows.map(Person.fromMap).toList();
  }

  Future<Person?> getPerson(int id) async {
    final db = await _db;
    final rows = await db.query('people', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Person.fromMap(rows.first);
  }

  Future<List<Person>> findPeopleByExactName(String name) async {
    final db = await _db;
    final rows = await db.query('people',
        where: 'name = ?', whereArgs: [name.trim()], orderBy: 'id');
    return rows.map(Person.fromMap).toList();
  }

  Future<int> insertPerson(Person person) async {
    final db = await _db;
    return db.insert('people', person.toMap()..remove('id'));
  }

  Future<void> updatePerson(Person person) async {
    final db = await _db;
    await db.update('people', person.toMap(),
        where: 'id = ?', whereArgs: [person.id]);
  }

  /// 사람을 지우면 그 사람의 내역도 함께 지워진다 (ON DELETE CASCADE).
  Future<void> deletePerson(int id) async {
    final db = await _db;
    await db.delete('people', where: 'id = ?', whereArgs: [id]);
  }

  // ───────────────────────── 내역 ─────────────────────────

  Future<int> countRecords() async {
    final db = await _db;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM records')) ?? 0;
  }

  Future<List<GiftRecord>> recordsForPerson(int personId) async {
    final db = await _db;
    final rows = await db.rawQuery(
        '$_recordSelect WHERE r.person_id = ? ORDER BY r.date DESC, r.id DESC',
        [personId]);
    return rows.map(GiftRecord.fromMap).toList();
  }

  Future<List<GiftRecord>> recordsForEvent(int eventId) async {
    final db = await _db;
    final rows = await db.rawQuery(
        '$_recordSelect WHERE r.event_id = ? ORDER BY r.id DESC', [eventId]);
    return rows.map(GiftRecord.fromMap).toList();
  }

  Future<List<GiftRecord>> recentRecords(int limit) async {
    final db = await _db;
    final rows = await db.rawQuery(
        '$_recordSelect ORDER BY r.date DESC, r.id DESC LIMIT ?', [limit]);
    return rows.map(GiftRecord.fromMap).toList();
  }

  Future<List<GiftRecord>> allRecords() async {
    final db = await _db;
    final rows =
        await db.rawQuery('$_recordSelect ORDER BY r.date DESC, r.id DESC');
    return rows.map(GiftRecord.fromMap).toList();
  }

  Future<int> insertRecord(GiftRecord record) async {
    final db = await _db;
    return db.insert('records', record.toMap()..remove('id'));
  }

  Future<void> updateRecord(GiftRecord record) async {
    final db = await _db;
    await db.update('records', record.toMap(),
        where: 'id = ?', whereArgs: [record.id]);
  }

  Future<void> deleteRecord(int id) async {
    final db = await _db;
    await db.delete('records', where: 'id = ?', whereArgs: [id]);
  }

  // ───────────────────────── 행사 ─────────────────────────

  Future<int> countMyEvents() async {
    final db = await _db;
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM events WHERE is_mine = 1')) ??
        0;
  }

  Future<List<EventSummary>> eventSummaries() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT e.*, COUNT(r.id) AS rec_count, COALESCE(SUM(r.amount), 0) AS rec_total
      FROM events e
      LEFT JOIN records r ON r.event_id = e.id
        AND r.direction = CASE WHEN e.is_mine = 1 THEN '받음' ELSE '보냄' END
      GROUP BY e.id
      ORDER BY e.date DESC, e.id DESC
    ''');
    return rows
        .map((r) => EventSummary(
              event: Event.fromMap(r),
              count: r['rec_count'] as int? ?? 0,
              total: r['rec_total'] as int? ?? 0,
            ))
        .toList();
  }

  Future<Event?> getEvent(int id) async {
    final db = await _db;
    final rows = await db.query('events', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Event.fromMap(rows.first);
  }

  static const _scheduleSelect = '''
    SELECT e.*, p.relation AS person_relation
    FROM events e
    LEFT JOIN people p ON p.id = e.person_id
  ''';

  /// 다가오는 일정 (남의 행사만)
  Future<List<Event>> upcomingSchedules({int? limit}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      $_scheduleSelect
      WHERE e.is_mine = 0 AND e.date >= ?
      ORDER BY e.date ASC, e.id ASC
      LIMIT ?
    ''', [toDbDate(DateTime.now()), limit ?? -1]);
    return rows.map(Event.fromMap).toList();
  }

  /// '얼마 내셨어요?': 날짜가 지났는데 보낸 기록이 없고 숨기지 않은 일정 (최근 순)
  Future<List<Event>> pendingAmountEvents({int? limit}) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      $_scheduleSelect
      WHERE e.is_mine = 0 AND e.pending_hidden = 0 AND e.date < ?
        AND NOT EXISTS (
          SELECT 1 FROM records r
          WHERE r.event_id = e.id AND r.direction = '보냄'
        )
      ORDER BY e.date DESC, e.id DESC
      LIMIT ?
    ''', [toDbDate(DateTime.now()), limit ?? -1]);
    return rows.map(Event.fromMap).toList();
  }

  /// '안 갔어요': 카드에서 숨긴다. 일정 자체는 남는다.
  Future<void> hidePendingEvent(int id) async {
    final db = await _db;
    await db.update('events', {'pending_hidden': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countSchedules() async {
    final db = await _db;
    return Sqflite.firstIntValue(await db
            .rawQuery('SELECT COUNT(*) FROM events WHERE is_mine = 0')) ??
        0;
  }

  /// 내 행사 (최근 날짜 순)
  Future<List<Event>> myEvents() async {
    final db = await _db;
    final rows = await db.query('events',
        where: 'is_mine = 1', orderBy: 'date DESC, id DESC');
    return rows.map(Event.fromMap).toList();
  }

  Future<List<Event>> allEvents() async {
    final db = await _db;
    final rows = await db.query('events', orderBy: 'date ASC');
    return rows.map(Event.fromMap).toList();
  }

  Future<int> insertEvent(Event event) async {
    final db = await _db;
    return db.insert('events', event.toMap()..remove('id'));
  }

  Future<void> updateEvent(Event event) async {
    final db = await _db;
    await db.update('events', event.toMap(),
        where: 'id = ?', whereArgs: [event.id]);
  }

  /// 내 행사의 받기 설정 (구분 · 식권 · 결제 방법)
  Future<void> updateEventReceiveSettings(Event event) async {
    final db = await _db;
    await db.update(
        'events',
        {
          'sides': jsonEncode(event.sides),
          'meal_ticket_enabled': event.mealTicketEnabled ? 1 : 0,
          'default_meal_tickets': event.defaultMealTickets,
          'method_enabled': event.methodEnabled ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [event.id]);
  }

  Future<void> setEventMealTicketEnabled(int id, bool enabled) async {
    final db = await _db;
    await db.update('events', {'meal_ticket_enabled': enabled ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 행사를 지워도 내역은 남는다 (행사 연결만 끊김).
  Future<void> deleteEvent(int id) async {
    final db = await _db;
    await db.delete('events', where: 'id = ?', whereArgs: [id]);
  }

  // ───────────────────────── 접수 모드 ─────────────────────────

  Future<void> insertReception(Reception reception) async {
    final db = await _db;
    await db.insert('receptions', reception.toMap());
  }

  Future<List<ReceptionSummary>> receptionSummaries() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT rc.*, COUNT(en.id) AS entry_count,
        COALESCE(SUM(en.amount), 0) AS entry_total
      FROM receptions rc
      LEFT JOIN reception_entries en
        ON en.reception_id = rc.id AND en.deleted = 0
      GROUP BY rc.id
      ORDER BY rc.started_at DESC
    ''');
    return rows
        .map((r) => ReceptionSummary(
              Reception.fromMap(r),
              r['entry_count'] as int? ?? 0,
              r['entry_total'] as int? ?? 0,
            ))
        .toList();
  }

  /// 대신 받은 장부와 지우지 않은 항목(최신이 앞). 없으면 null.
  Future<ReceptionPackage?> getReceptionPackage(String id) async {
    final db = await _db;
    final rows = await db.query('receptions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final entries = await db.query('reception_entries',
        where: 'reception_id = ? AND deleted = 0',
        whereArgs: [id],
        orderBy: 'created_at DESC, rowid DESC');
    return ReceptionPackage(Reception.fromMap(rows.first),
        entries.map(ReceptionEntry.fromMap).toList());
  }

  Future<void> setReceptionFinished(String id, {required bool finished}) async {
    final db = await _db;
    await db.update(
        'receptions',
        {'finished_at': finished ? DateTime.now().toIso8601String() : null},
        where: 'id = ?',
        whereArgs: [id]);
  }

  Future<void> setReceptionMealTicketEnabled(String id, bool enabled) async {
    final db = await _db;
    await db.update('receptions', {'meal_ticket_enabled': enabled ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteReception(String id) async {
    final db = await _db;
    await db.delete('receptions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> insertReceptionEntry(ReceptionEntry entry) async {
    final db = await _db;
    await db.insert('reception_entries', entry.toMap());
  }

  Future<void> updateReceptionEntry(ReceptionEntry entry) async {
    final db = await _db;
    await db.update('reception_entries', entry.toMap(),
        where: 'id = ?', whereArgs: [entry.id]);
  }

  /// 되돌리기 · 삭제: 표시만 해 두고 합계와 보내기에서 뺀다.
  Future<void> deleteReceptionEntry(String id) async {
    final db = await _db;
    await db.update('reception_entries', {'deleted': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 사람 · 기록 · 일정 · 접수 중 하나라도 있으면 true
  Future<bool> hasAnyData() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT EXISTS(SELECT 1 FROM people)
        OR EXISTS(SELECT 1 FROM records)
        OR EXISTS(SELECT 1 FROM events)
        OR EXISTS(SELECT 1 FROM receptions)
    ''');
    return Sqflite.firstIntValue(rows) == 1;
  }

  Future<void> snapshotTo(String outPath) => _helper.snapshotTo(outPath);

  // ───────────────────────── 테스트 전용 더미 데이터 ─────────────────────────

  Future<bool> hasDummyData() async {
    final db = await _db;
    final rows = await db.rawQuery(
        'SELECT EXISTS(SELECT 1 FROM people WHERE memo = ?) '
        'OR EXISTS(SELECT 1 FROM events WHERE memo = ?)',
        [dummyDataMarker, dummyDataMarker]);
    return Sqflite.firstIntValue(rows) == 1;
  }

  /// 더미 사람 · 행사만 지운다. 더미 사람의 기록은 함께 지워진다.
  Future<void> deleteDummyData() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('people', where: 'memo = ?', whereArgs: [dummyDataMarker]);
      await txn.delete('events', where: 'memo = ?', whereArgs: [dummyDataMarker]);
    });
  }

  Future<int> countReceptionEntries() async {
    final db = await _db;
    return Sqflite.firstIntValue(await db
            .rawQuery('SELECT COUNT(*) FROM reception_entries WHERE deleted = 0')) ??
        0;
  }

  // ───────────────────────── 받은 장부 가져오기 ─────────────────────────

  /// [maxPeople]은 전체 사람 수 한도. null이면 제한 없음.
  Future<ImportPlan> planImport(ReceptionPackage package,
      {int? eventId, int? maxPeople}) async {
    return _planImport(await _db, package, eventId, maxPeople);
  }

  Future<ImportPlan> _planImport(DatabaseExecutor db, ReceptionPackage package,
      int? eventId, int? maxPeople) async {
    final imported = await db.query('imported_entries', columns: ['entry_id']);
    final people = await db.query('people', columns: ['id', 'name'], orderBy: 'id');
    final peopleByName = <String, List<int>>{};
    for (final row in people) {
      peopleByName.putIfAbsent(row['name'] as String, () => []).add(row['id'] as int);
    }
    final inEvent = eventId == null
        ? const <Map<String, Object?>>[]
        : await db.rawQuery('''
            SELECT DISTINCT p.name AS name FROM records r
            JOIN people p ON p.id = r.person_id
            WHERE r.event_id = ?
          ''', [eventId]);
    return buildImportPlan(
      entries: package.entries,
      importedIds: imported.map((r) => r['entry_id'] as String).toSet(),
      peopleByName: peopleByName,
      namesInEvent: inEvent.map((r) => r['name'] as String).toSet(),
      newPersonSlots:
          maxPeople == null ? null : (maxPeople - people.length).clamp(0, maxPeople),
    );
  }

  /// 계획대로 내 장부에 넣는다. 도중에 실패하면 아무것도 저장되지 않는다.
  /// [eventId]가 null이면 [newEvent]를 새 장부로 만든다.
  Future<({int eventId, ImportPlan plan})> applyImport(
    ReceptionPackage package, {
    int? eventId,
    Event? newEvent,
    int? maxPeople,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final targetId =
          eventId ?? await txn.insert('events', newEvent!.toMap()..remove('id'));
      final event = (await txn.query('events',
              where: 'id = ?', whereArgs: [targetId]))
          .first;
      final plan = await _planImport(txn, package, targetId, maxPeople);
      final newPeople = <String, int>{};
      final now = DateTime.now().toIso8601String();
      for (final item in plan.items) {
        final entry = item.entry;
        final name = entry.name.trim();
        final personId = item.personId ??
            newPeople[name] ??
            (newPeople[name] = await txn.insert(
                'people', Person(name: name, createdAt: DateTime.now()).toMap()..remove('id')));
        // 구분 · 식권은 따로 저장하고, 메모에는 접수 때 적은 메모만 넣는다.
        final memo = (entry.memo ?? '').trim();
        final hasSide =
            entry.side.isNotEmpty && entry.side != ReceptionDefaults.noSide;
        await txn.insert('records', {
          'person_id': personId,
          'event_id': targetId,
          'direction': '받음',
          'amount': entry.amount,
          'method': entry.method,
          'date': event['date'],
          'memo': memo.isEmpty ? null : memo,
          'needs_review': item.needsReview ? 1 : 0,
          'side': hasSide ? entry.side : null,
          'meal_tickets': entry.mealTickets,
        });
        await txn.insert(
            'imported_entries', {'entry_id': entry.id, 'imported_at': now});
      }
      if (plan.skippedByLimit == 0) {
        // 이 기기에서 접수한 장부라면 '옮김'으로 표시
        await txn.update('receptions', {'imported': 1},
            where: 'id = ?', whereArgs: [package.reception.id]);
      }
      return (eventId: targetId, plan: plan);
    });
  }

  /// 확인 필요 내역: 같은 사람이 맞다고 확인
  Future<void> markRecordReviewed(int recordId) async {
    final db = await _db;
    await db.update('records', {'needs_review': 0},
        where: 'id = ?', whereArgs: [recordId]);
  }

  /// 확인 필요 내역: 다른 사람이므로 같은 이름의 새 사람으로 분리
  Future<void> moveRecordToNewPerson(int recordId, String name) async {
    final db = await _db;
    await db.transaction((txn) async {
      final personId = await txn.insert('people',
          Person(name: name, createdAt: DateTime.now()).toMap()..remove('id'));
      await txn.update('records', {'person_id': personId, 'needs_review': 0},
          where: 'id = ?', whereArgs: [recordId]);
    });
  }

  // ───────────────────────── 통계 ─────────────────────────

  /// 해당 연도의 보냄/받음 총액과 건수
  Future<({int sent, int received, int sentCount, int receivedCount})>
      yearTotals(int year) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN direction = '보냄' THEN amount END), 0) AS sent,
        COALESCE(SUM(CASE WHEN direction = '받음' THEN amount END), 0) AS received,
        COUNT(CASE WHEN direction = '보냄' THEN 1 END) AS sent_count,
        COUNT(CASE WHEN direction = '받음' THEN 1 END) AS received_count
      FROM records WHERE substr(date, 1, 4) = ?
    ''', ['$year']);
    final r = rows.first;
    return (
      sent: r['sent'] as int? ?? 0,
      received: r['received'] as int? ?? 0,
      sentCount: r['sent_count'] as int? ?? 0,
      receivedCount: r['received_count'] as int? ?? 0,
    );
  }

  /// 월별(1~12) 보냄/받음 합계
  Future<List<({int month, int sent, int received})>> monthlyTotals(
      int year) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT CAST(substr(date, 6, 2) AS INTEGER) AS m,
        COALESCE(SUM(CASE WHEN direction = '보냄' THEN amount END), 0) AS sent,
        COALESCE(SUM(CASE WHEN direction = '받음' THEN amount END), 0) AS received
      FROM records WHERE substr(date, 1, 4) = ?
      GROUP BY m
    ''', ['$year']);
    final byMonth = {for (final r in rows) r['m'] as int: r};
    return List.generate(12, (i) {
      final r = byMonth[i + 1];
      return (
        month: i + 1,
        sent: r?['sent'] as int? ?? 0,
        received: r?['received'] as int? ?? 0,
      );
    });
  }

  /// 관계별 보냄/받음 합계 (해당 연도)
  Future<List<({String relation, int sent, int received})>> relationTotals(
      int year) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT p.relation AS relation,
        COALESCE(SUM(CASE WHEN r.direction = '보냄' THEN r.amount END), 0) AS sent,
        COALESCE(SUM(CASE WHEN r.direction = '받음' THEN r.amount END), 0) AS received
      FROM records r JOIN people p ON p.id = r.person_id
      WHERE substr(r.date, 1, 4) = ?
      GROUP BY p.relation
    ''', ['$year']);
    return rows
        .map((r) => (
              relation: r['relation'] as String,
              sent: r['sent'] as int? ?? 0,
              received: r['received'] as int? ?? 0,
            ))
        .toList();
  }

  /// 연도별 보냄/받음 합계
  Future<List<({int year, int sent, int received})>> yearlyTotals() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT CAST(substr(date, 1, 4) AS INTEGER) AS y,
        COALESCE(SUM(CASE WHEN direction = '보냄' THEN amount END), 0) AS sent,
        COALESCE(SUM(CASE WHEN direction = '받음' THEN amount END), 0) AS received
      FROM records GROUP BY y ORDER BY y
    ''');
    return rows
        .map((r) => (
              year: r['y'] as int,
              sent: r['sent'] as int? ?? 0,
              received: r['received'] as int? ?? 0,
            ))
        .toList();
  }

  /// 내역이 있는 연도 목록 (+올해)
  Future<List<int>> recordYears() async {
    final db = await _db;
    final rows = await db.rawQuery(
        'SELECT DISTINCT CAST(substr(date, 1, 4) AS INTEGER) AS y FROM records ORDER BY y');
    final years = rows.map((r) => r['y'] as int).toSet()
      ..add(DateTime.now().year);
    return years.toList()..sort();
  }
}
