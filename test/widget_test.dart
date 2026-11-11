import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/models/gift_record.dart';
import 'package:gyeongjosa/services/csv_service.dart';
import 'package:gyeongjosa/services/format.dart';
import 'package:gyeongjosa/services/notification_service.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  test('금액은 50,000원 형식', () {
    expect(formatWon(50000), '50,000원');
    expect(formatManWon(100000), '10만');
    expect(formatReadableWon(70000), '7만원');
    expect(formatReadableWon(35000), '3만 5천원');
    expect(formatReadableWon(12345), '1만 2,345원');
    expect(formatReadableWon(5000), '5천원');
    expect(formatReadableWon(1000000), '100만원');
    expect(formatReadableWon(150000000), '1억 5,000만원');
  });

  group('백업 배너', () {
    final now = DateTime(2026, 11, 3);
    test('기록 20개 미만, 백업 안 함 → 안 보임', () {
      expect(
          shouldShowBackupBanner(
              recordCount: 19, lastBackup: null, dismissedAt: null, now: now),
          isFalse);
    });
    test('기록 20개 이상, 백업 안 함 → 보임', () {
      expect(
          shouldShowBackupBanner(
              recordCount: 20, lastBackup: null, dismissedAt: null, now: now),
          isTrue);
    });
    test('마지막 백업 후 30일 지남 → 보임', () {
      expect(
          shouldShowBackupBanner(
              recordCount: 5,
              lastBackup: now.subtract(const Duration(days: 30)),
              dismissedAt: null,
              now: now),
          isTrue);
    });
    test('닫은 지 7일 안 → 안 보임', () {
      expect(
          shouldShowBackupBanner(
              recordCount: 50,
              lastBackup: null,
              dismissedAt: now.subtract(const Duration(days: 2)),
              now: now),
          isFalse);
    });
  });

  test('CSV는 UTF-8 BOM으로 시작하고, 쉼표가 든 값은 큰따옴표로 감싼다', () {
    final csv = CsvService.buildCsv(records: [
      GiftRecord(
        personId: 1,
        direction: '받음',
        amount: 50000,
        date: DateTime(2026, 5, 2),
        eventType: '결혼',
        personName: '김철수',
        personRelation: '친구',
        memo: '봉투, 꽃',
      ),
    ], events: const []);
    expect(csv.startsWith('﻿'), isTrue);
    expect(csv, contains('번호,이름,관계,구분,금액,결제 방법,식권,메모,날짜'));
    expect(csv, contains('1,김철수,친구,,50000,현금,,"봉투, 꽃",2026-05-02'));
  });

  test('알림은 행사 전날 오전 9시', () {
    expect(NotificationService.reminderTime(DateTime(2026, 3, 1)),
        DateTime(2026, 2, 28, 9));
  });
}
