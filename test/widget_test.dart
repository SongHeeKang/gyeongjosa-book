import 'package:flutter_test/flutter_test.dart';
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


  test('알림은 행사 전날 오전 9시', () {
    expect(NotificationService.reminderTime(DateTime(2026, 3, 1)),
        DateTime(2026, 2, 28, 9));
  });
}
