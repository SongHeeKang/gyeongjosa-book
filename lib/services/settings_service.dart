import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// main()에서 SharedPreferences를 미리 열어 override 한다.
final prefsProvider = Provider<SharedPreferences>(
    (ref) => throw UnimplementedError('prefsProvider must be overridden'));

class PrefKeys {
  static const lastBackupAt = 'last_backup_at';
  static const backupBannerDismissedAt = 'backup_banner_dismissed_at';
  static const notifPermissionAsked = 'notif_permission_asked';
  static const proPurchased = 'pro_purchased';
  static const devProOverride = 'dev_pro_override';
  static const quickEntryRelation = 'quick_entry_relation';
  static const receptionOperator = 'reception_operator';

  /// 접수 장부별 마지막 구분
  static String receptionLastSide(String receptionId) =>
      'reception_last_side_$receptionId';
}

/// 마지막 수동 백업 시각
class LastBackupNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    final s = ref.watch(prefsProvider).getString(PrefKeys.lastBackupAt);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> markNow() async {
    final now = DateTime.now();
    await ref
        .read(prefsProvider)
        .setString(PrefKeys.lastBackupAt, now.toIso8601String());
    state = now;
  }
}

final lastBackupProvider =
    NotifierProvider<LastBackupNotifier, DateTime?>(LastBackupNotifier.new);

/// 홈 백업 배너를 닫은 시각 (닫으면 7일 동안 다시 안 보임)
class BannerDismissNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    final s =
        ref.watch(prefsProvider).getString(PrefKeys.backupBannerDismissedAt);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> dismiss() async {
    final now = DateTime.now();
    await ref.read(prefsProvider).setString(
        PrefKeys.backupBannerDismissedAt, now.toIso8601String());
    state = now;
  }
}

final bannerDismissProvider =
    NotifierProvider<BannerDismissNotifier, DateTime?>(
        BannerDismissNotifier.new);

/// 백업 알림 배너를 보여줄지 결정.
/// 기록 20개 이상인데 수동 백업을 한 번도 안 했거나, 마지막 백업 후 30일이 지나면 표시.
bool shouldShowBackupBanner({
  required int recordCount,
  required DateTime? lastBackup,
  required DateTime? dismissedAt,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  if (dismissedAt != null && today.difference(dismissedAt).inDays < 7) {
    return false;
  }
  if (lastBackup == null) return recordCount >= 20;
  return today.difference(lastBackup).inDays >= 30;
}
