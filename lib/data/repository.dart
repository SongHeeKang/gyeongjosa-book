import 'package:sqflite/sqflite.dart';

import '../models/event.dart';
import '../models/gift_record.dart';
import '../models/person.dart';
import '../services/format.dart';
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

  Future<List<Event>> upcomingEvents({int? limit}) async {
    final db = await _db;
    final rows = await db.query('events',
        where: 'date >= ?',
        whereArgs: [toDbDate(DateTime.now())],
        orderBy: 'date ASC, id ASC',
        limit: limit);
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

  /// 행사를 지워도 내역은 남는다 (행사 연결만 끊김).
  Future<void> deleteEvent(int id) async {
    final db = await _db;
    await db.delete('events', where: 'id = ?', whereArgs: [id]);
  }

  // ───────────────────────── 통계 ─────────────────────────

  /// 해당 연도의 보냄/받음 총액
  Future<({int sent, int received})> yearTotals(int year) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN direction = '보냄' THEN amount END), 0) AS sent,
        COALESCE(SUM(CASE WHEN direction = '받음' THEN amount END), 0) AS received
      FROM records WHERE substr(date, 1, 4) = ?
    ''', ['$year']);
    final r = rows.first;
    return (sent: r['sent'] as int? ?? 0, received: r['received'] as int? ?? 0);
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
