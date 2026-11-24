import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import 'notification_service.dart';
import 'settings_service.dart';

/// 알림 권한이 있는지. 행사 전날 알림처럼 알림이 필요한 기능은 이 값을 보고
/// 권한이 없으면 막는다. 앱을 켤 때 · 앱으로 돌아올 때 다시 확인한다.
class NotificationPermission extends Notifier<bool> {
  /// 확인 전에는 '있음'으로 두어 화면이 잠깐 막혔다 풀리지 않게 한다.
  @override
  bool build() => true;

  /// 지금 권한을 다시 확인한다. 꺼져 있다가 켜졌으면 행사 알림을 다시 건다.
  Future<bool> refresh() async {
    final enabled = await NotificationService.instance.areEnabled();
    final wasEnabled = state;
    state = enabled;
    if (enabled && !wasEnabled) {
      final events = await ref.read(repositoryProvider).allEvents();
      await NotificationService.instance.resyncAll(events);
    }
    return enabled;
  }
}

final notificationPermissionProvider =
    NotifierProvider<NotificationPermission, bool>(NotificationPermission.new);

const _settingsChannel = MethodChannel('gyeongjosa/notifications');

/// 휴대폰 설정의 이 앱 알림 화면을 연다.
Future<void> openNotificationSettings() async {
  try {
    await _settingsChannel.invokeMethod<void>('openSettings');
  } catch (e) {
    debugPrint('알림 설정 열기 실패: $e');
  }
}

/// 알림 권한을 확인하고, 없으면 이유를 설명한 뒤 요청한다. 있으면 묻지 않고 true.
///
/// 안드로이드는 두 번 거절하면 더 이상 허용 창을 띄우지 않으므로, 그때는 휴대폰 설정의
/// 알림 화면으로 보낸다. [atLaunch]는 앱을 켤 때 묻는 경우(문구만 다르다).
Future<bool> askNotificationPermission(BuildContext context, WidgetRef ref,
    {bool atLaunch = false}) async {
  if (await ref.read(notificationPermissionProvider.notifier).refresh()) {
    return true;
  }
  if (!context.mounted) return false;

  final prefs = ref.read(prefsProvider);
  final denied = prefs.getInt(PrefKeys.notifDeniedCount) ?? 0;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('알림을 허용해 주세요'),
      // 추가 AC: 설명은 한 줄만
      content: const Text('일정마다 원하는 날짜와 시간에 알려드려요'),
      actions: [
        TextButton(
            key: const ValueKey('notif_later'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('허용 안 함')),
        FilledButton(
            key: const ValueKey('notif_allow'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(denied >= 2 ? '설정에서 켜기' : '허용하기')),
      ],
    ),
  );
  await prefs.setBool(PrefKeys.notifPermissionAsked, true);
  // '허용 안 함'이면 조용히 넘어간다(스낵바 없음). 홈 일정 아래 '알림이 꺼져 있어요 · 켜기'로 다시 켤 수 있다.
  if (ok != true) return false;
  final granted = await requestNotificationsOrOpenSettings(ref);
  // 앱을 켤 때는 허용 창에서 거절해도 스낵바를 띄우지 않는다.
  if (!granted && !atLaunch && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('알림을 허용하지 않아 행사 알림은 쓸 수 없어요.')));
  }
  return granted;
}

/// 설명 없이 바로 알림 허용 창을 띄운다. 더 이상 허용 창을 띄울 수 없는 상태면
/// 휴대폰 설정의 이 앱 알림 화면을 연다(돌아오면 [NotificationPermission.refresh]로 다시 확인).
/// 홈의 '알림이 꺼져 있어요 · [켜기]'와 위 [askNotificationPermission]에서 쓴다.
Future<bool> requestNotificationsOrOpenSettings(WidgetRef ref) async {
  final permission = ref.read(notificationPermissionProvider.notifier);
  final prefs = ref.read(prefsProvider);
  final denied = prefs.getInt(PrefKeys.notifDeniedCount) ?? 0;
  if (denied >= 2) {
    // 안드로이드는 두 번 거절하면 허용 창을 더 띄우지 않으므로 설정 화면으로.
    await openNotificationSettings();
    return false;
  }
  final started = DateTime.now();
  final granted = await NotificationService.instance.requestPermission();
  if (granted) {
    await prefs.setInt(PrefKeys.notifDeniedCount, 0);
    await permission.refresh();
    return true;
  }
  await prefs.setInt(PrefKeys.notifDeniedCount, denied + 1);
  // 허용 창이 뜨지도 않고 바로 거절되면(이미 막힌 경우) 설정 화면으로 보낸다.
  if (DateTime.now().difference(started) < const Duration(milliseconds: 400)) {
    await prefs.setInt(PrefKeys.notifDeniedCount, 2);
    await openNotificationSettings();
  }
  return false;
}

/// 일정 알림에서 [없음]이 아닌 값을 고를 때 (추가 AC).
/// 권한이 있으면 아무것도 하지 않는다. 안드로이드가 아직 허용 창을 띄울 수 있으면 바로 허용 창,
/// 더 띄울 수 없는 상태(두 번 거절 등)면 "알림이 꺼져 있어 이 일정 알림을 받을 수 없어요"
/// [설정 열기] [나중에]. 어느 경우든 고른 값과 저장은 막지 않는다(돌려주는 값은 권한 여부).
Future<bool> ensureReminderPermission(BuildContext context, WidgetRef ref) async {
  final permission = ref.read(notificationPermissionProvider.notifier);
  if (await permission.refresh()) return true;
  final prefs = ref.read(prefsProvider);
  final denied = prefs.getInt(PrefKeys.notifDeniedCount) ?? 0;
  if (denied < 2) {
    final started = DateTime.now();
    final granted = await NotificationService.instance.requestPermission();
    if (granted) {
      await prefs.setInt(PrefKeys.notifDeniedCount, 0);
      await permission.refresh();
      return true;
    }
    final blocked =
        DateTime.now().difference(started) < const Duration(milliseconds: 400);
    await prefs.setInt(PrefKeys.notifDeniedCount, blocked ? 2 : denied + 1);
    // 허용 창이 뜨지도 않고 바로 거절되면(이미 막힌 경우) 아래 안내로
    if (!blocked) return false;
  }
  if (!context.mounted) return false;
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: const Text('알림이 꺼져 있어 이 일정 알림을 받을 수 없어요'),
      actions: [
        TextButton(
            key: const ValueKey('reminder_perm_later'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('나중에')),
        FilledButton(
            key: const ValueKey('reminder_perm_settings'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('설정 열기')),
      ],
    ),
  );
  if (open == true) await openNotificationSettings();
  return false;
}
