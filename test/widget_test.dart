import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/widgets/backup_guide.dart';
import 'package:gyeongjosa/services/format.dart';
import 'package:gyeongjosa/services/notification_service.dart';
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

  group('홈 백업 아이콘 상태 (추가 W)', () {
    final now = DateTime(2026, 11, 20, 15);
    test('7일 이내 백업 → 초록 체크', () {
      expect(
          backupStatus(
              recordCount: 3,
              lastBackup: now.subtract(const Duration(days: 7)),
              now: now),
          BackupStatus.ok);
    });
    test('기록이 있는데 백업 없음 → 주황 점', () {
      expect(backupStatus(recordCount: 1, lastBackup: null, now: now),
          BackupStatus.due);
    });
    test('기록이 없고 백업 없음 → 회색', () {
      expect(backupStatus(recordCount: 0, lastBackup: null, now: now),
          BackupStatus.normal);
    });
    test('8~30일 → 회색, 30일 지남 → 주황 점', () {
      expect(
          backupStatus(
              recordCount: 5,
              lastBackup: now.subtract(const Duration(days: 20)),
              now: now),
          BackupStatus.normal);
      expect(
          backupStatus(
              recordCount: 5,
              lastBackup: now.subtract(const Duration(days: 31)),
              now: now),
          BackupStatus.due);
    });
    test('마지막 백업 시각 표시', () {
      expect(formatBackupTime(DateTime(2026, 11, 20, 15, 12)),
          '2026.11.20 오후 3:12');
    });
  });

  test('알림은 행사 전날 오전 9시', () {
    expect(NotificationService.reminderTime(DateTime(2026, 3, 1)),
        DateTime(2026, 2, 28, 9));
  });
}
