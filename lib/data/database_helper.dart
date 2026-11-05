import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 기기 안 SQLite DB를 열고, 버전이 바뀌면 기존 데이터를 지키면서 구조만 업그레이드한다.
///
/// 새 기능 때문에 테이블 구조를 바꿀 때는:
/// 1. [_dbVersion]을 1 올리고
/// 2. [_migrations]에 "이전 버전 → 새 버전" 단계를 추가한다.
/// (DROP TABLE 처럼 데이터를 지우는 변경은 하지 않는다)
class DatabaseHelper {
  DatabaseHelper._([this._pathOverride, this._singleInstance = true]);
  static final DatabaseHelper instance = DatabaseHelper._();

  /// 테스트 전용: 실제 앱 데이터와 분리된 파일을 쓴다.
  @visibleForTesting
  factory DatabaseHelper.forTest(String path) => DatabaseHelper._(path);

  /// 앱 본체와 따로 여는 연결. 데이터 관리 화면처럼 앱 본체가 뒤에서 켜져 있을 수 있는
  /// 곳에서 쓴다. 공유 연결을 닫으면 앱 본체의 DB까지 닫히기 때문이다.
  factory DatabaseHelper.separateConnection() => DatabaseHelper._(null, false);

  static const dbFileName = 'gyeongjosa.db';
  static const _dbVersion = 4;

  final String? _pathOverride;
  final bool _singleInstance;
  Database? _db;

  Future<Database> get database async {
    final db = _db;
    if (db != null && db.isOpen) return db;
    _db = await _open();
    return _db!;
  }

  Future<String> get dbPath async =>
      _pathOverride ?? p.join(await getDatabasesPath(), dbFileName);

  Future<Database> _open() async {
    return openDatabase(
      await dbPath,
      version: _dbVersion,
      singleInstance: _singleInstance,
      onConfigure: (db) async {
        // 사람을 지우면 그 사람의 내역도 같이 지워지도록 외래키 사용
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createV1(db);
        for (var v = 2; v <= version; v++) {
          await _migrations[v]!(db);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        for (var v = oldVersion + 1; v <= newVersion; v++) {
          await _migrations[v]!(db);
        }
      },
    );
  }

  /// 최초 버전(1)의 테이블 구조
  static Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE people (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        relation TEXT NOT NULL DEFAULT '기타',
        phone TEXT,
        memo TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL DEFAULT '기타',
        title TEXT NOT NULL,
        date TEXT NOT NULL,
        is_mine INTEGER NOT NULL DEFAULT 0,
        place TEXT,
        memo TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        person_id INTEGER NOT NULL REFERENCES people(id) ON DELETE CASCADE,
        event_id INTEGER REFERENCES events(id) ON DELETE SET NULL,
        direction TEXT NOT NULL,
        amount INTEGER NOT NULL,
        method TEXT NOT NULL DEFAULT '현금',
        date TEXT NOT NULL,
        memo TEXT
      )
    ''');
  }

  /// 버전별 업그레이드 단계. key = 올라갈 버전
  static final Map<int, Future<void> Function(Database db)> _migrations = {
    // v2: 행사 알림 여부, 행사와 연결 안 된 내역의 행사 종류, 검색용 인덱스
    2: (db) async {
      await db.execute(
          'ALTER TABLE events ADD COLUMN notify INTEGER NOT NULL DEFAULT 1');
      await db.execute('ALTER TABLE records ADD COLUMN event_type TEXT');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_records_person ON records(person_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_records_event ON records(event_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_records_date ON records(date)');
    },
    // v3: 접수 모드 (접수 장부, 접수 항목, 가져온 항목 기록, 확인 필요 표시)
    3: (db) async {
      await db.execute('''
        CREATE TABLE receptions (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          event_type TEXT NOT NULL DEFAULT '기타',
          date TEXT NOT NULL,
          sides TEXT NOT NULL,
          operator_name TEXT NOT NULL DEFAULT '',
          started_at TEXT NOT NULL,
          finished_at TEXT,
          imported INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE reception_entries (
          id TEXT PRIMARY KEY,
          reception_id TEXT NOT NULL REFERENCES receptions(id) ON DELETE CASCADE,
          name TEXT NOT NULL,
          amount INTEGER NOT NULL,
          side TEXT NOT NULL DEFAULT '',
          method TEXT NOT NULL DEFAULT '현금',
          meal_tickets INTEGER NOT NULL DEFAULT 1,
          memo TEXT,
          created_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute(
          'CREATE INDEX idx_entries_reception ON reception_entries(reception_id)');
      // 내역을 나중에 지워도 같은 파일을 다시 가져올 때 되살아나지 않도록 따로 기록한다.
      await db.execute('''
        CREATE TABLE imported_entries (
          entry_id TEXT PRIMARY KEY,
          imported_at TEXT NOT NULL
        )
      ''');
      await db.execute(
          'ALTER TABLE records ADD COLUMN needs_review INTEGER NOT NULL DEFAULT 0');
    },
    // v4: 일정에 사람 연결, '얼마 내셨어요?' 숨김 여부
    4: (db) async {
      await db.execute(
          'ALTER TABLE events ADD COLUMN person_id INTEGER REFERENCES people(id) ON DELETE SET NULL');
      await db.execute(
          'ALTER TABLE events ADD COLUMN pending_hidden INTEGER NOT NULL DEFAULT 0');
    },
  };

  /// DB를 닫지 않고 지금 내용을 파일 하나로 복사한다. 복사하는 동안 다른 저장은 잠깐 기다린다.
  Future<void> snapshotTo(String outPath) async {
    final db = await database;
    final source = await dbPath;
    // WAL에 남은 내용을 본 파일로 옮긴다. WAL을 안 쓰는 기기에서는 아무 일도 하지 않는다.
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    await db.transaction((_) async {
      await File(source).copy(outPath);
    });
  }

  /// 복원을 위해 DB를 닫는다.
  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null && db.isOpen) await db.close();
  }

  /// 복원할 파일이 이 앱의 백업 파일이 맞는지 검사한다.
  /// 문제가 있으면 사용자에게 보여줄 문구를 담은 [FormatException]을 던진다.
  static Future<void> validateBackupFile(String path) async {
    if (!await File(path).exists()) {
      throw const FormatException('파일을 찾을 수 없어요.');
    }
    Database? db;
    try {
      db = await openDatabase(path, readOnly: true, singleInstance: false);
      final tables = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'] as String)
          .toSet();
      if (!tables.containsAll(['people', 'events', 'records'])) {
        throw const FormatException('경조사 장부 백업 파일이 아니에요.');
      }
      final version = Sqflite.firstIntValue(
              await db.rawQuery('PRAGMA user_version')) ??
          0;
      if (version > _dbVersion) {
        throw const FormatException(
            '더 새로운 버전의 앱에서 만든 백업이에요. 앱을 업데이트한 뒤 다시 시도해 주세요.');
      }
    } on FormatException {
      rethrow;
    } catch (e) {
      debugPrint('백업 파일 검사 실패: $e');
      throw const FormatException('백업 파일을 읽을 수 없어요. 올바른 파일인지 확인해 주세요.');
    } finally {
      await db?.close();
    }
  }
}
