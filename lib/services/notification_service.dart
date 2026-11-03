import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/event.dart';
import 'settings_service.dart';

/// 행사 전날 오전 9시 알림.
/// - 정확한 알람 권한 없이 일반 예약 알림(inexactAllowWhileIdle) 사용 → 9시 전후 몇 분 차이 가능
/// - 재부팅 후 유지는 AndroidManifest의 ScheduledNotificationBootReceiver가 처리
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'event_reminder',
    '행사 알림',
    channelDescription: '행사 전날 오전 9시에 알려드려요',
    importance: Importance.high,
    priority: Priority.high,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('알림 초기화 실패: $e');
    }
  }

  /// 알림 시각: 행사 전날 오전 9시
  static DateTime reminderTime(DateTime eventDate) =>
      DateTime(eventDate.year, eventDate.month, eventDate.day - 1, 9);

  Future<void> scheduleForEvent(Event event) async {
    if (!_ready || event.id == null) return;
    await cancelForEvent(event.id!);
    if (!event.notify) return;

    final at = reminderTime(event.date);
    if (!at.isAfter(DateTime.now())) return; // 이미 지난 시각은 예약하지 않음

    final place = (event.place ?? '').trim();
    await _plugin.zonedSchedule(
      id: event.id!,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: const NotificationDetails(android: _channel),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: '내일 ${event.title}',
      body: place.isEmpty
          ? '${event.type} 행사가 내일이에요. 잊지 말고 챙기세요.'
          : '${event.type} · $place — 잊지 말고 챙기세요.',
    );
  }

  Future<void> cancelForEvent(int eventId) async {
    if (!_ready) return;
    await _plugin.cancel(id: eventId);
  }

  /// 모든 예약을 지우고 다시 건다 (앱 시작, 백업 복원 후).
  Future<void> resyncAll(List<Event> events) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    for (final e in events) {
      await scheduleForEvent(e);
    }
  }

  /// 개발 모드 테스트용: 바로 알림 띄우기
  Future<void> showTest() async {
    if (!_ready) return;
    await _plugin.show(
      id: 999999,
      title: '알림 테스트',
      body: '행사 알림이 이렇게 보여요.',
      notificationDetails: const NotificationDetails(android: _channel),
    );
  }

  Future<bool> areEnabled() async =>
      await _android?.areNotificationsEnabled() ?? true;

  /// Android 13 이상: 알림을 처음 켤 때 이유를 설명하고 권한을 요청한다.
  /// 허용되면 true.
  Future<bool> ensurePermission(
      BuildContext context, SharedPreferences prefs) async {
    if (await areEnabled()) return true;
    if (!context.mounted) return false;

    final asked = prefs.getBool(PrefKeys.notifPermissionAsked) ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('알림을 허용해 주세요'),
        content: Text(asked
            ? '알림이 꺼져 있어요.\n행사 전날 오전 9시에 알려드리려면 알림 허용이 필요해요.'
            : '행사 전날 오전 9시에 "내일 ○○ 결혼식이에요" 하고 알려드려요.\n다음 화면에서 알림을 허용해 주세요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('나중에')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('허용하기')),
        ],
      ),
    );
    await prefs.setBool(PrefKeys.notifPermissionAsked, true);
    if (ok != true) return false;
    final granted = await _android?.requestNotificationsPermission() ?? false;
    if (!granted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('알림이 꺼져 있어요. 휴대폰 설정 > 앱 > 경조사 장부 > 알림에서 켤 수 있어요.'),
      ));
    }
    return granted;
  }
}
