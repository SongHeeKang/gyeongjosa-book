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
  static const onboardingSeen = 'onboarding_seen';
  static const autoBackupEnabled = 'auto_backup_enabled';
  static const lastAutoBackupAt = 'last_auto_backup_at';
  static const autoBackupFileName = 'auto_backup_file_name';
  static const restorePromptDone = 'restore_prompt_done';

  /// 대신 받은 장부별 마지막 구분
  /// 내 행사 [장부 보내기] 파일의 항목 ID 앞에 붙이는 이 설치만의 값
  static const installId = 'install_id';

  static String eventLastSide(int eventId) => 'event_last_side_$eventId';

  static String receptionLastSide(String receptionId) =>
      'reception_last_side_$receptionId';
}

/// 첫 실행 가이드를 봤는지
class OnboardingSeenNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(prefsProvider).getBool(PrefKeys.onboardingSeen) ?? false;

  Future<void> markSeen() async {
    state = true;
    await ref.read(prefsProvider).setBool(PrefKeys.onboardingSeen, true);
  }

  /// 테스트용: 앱을 다시 켜면 가이드가 보이게 한다.
  Future<void> reset() =>
      ref.read(prefsProvider).remove(PrefKeys.onboardingSeen);
}

final onboardingSeenProvider =
    NotifierProvider<OnboardingSeenNotifier, bool>(OnboardingSeenNotifier.new);

/// 첫 실행 때 이전 백업을 불러올지 묻는 단계가 끝났는지. 끝난 뒤에 화면별 도움말을 띄운다.
class RestorePromptDoneNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(prefsProvider).getBool(PrefKeys.restorePromptDone) ?? false;

  Future<void> markDone() async {
    await ref.read(prefsProvider).setBool(PrefKeys.restorePromptDone, true);
    state = true;
  }
}

final restorePromptDoneProvider =
    NotifierProvider<RestorePromptDoneNotifier, bool>(
        RestorePromptDoneNotifier.new);

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
