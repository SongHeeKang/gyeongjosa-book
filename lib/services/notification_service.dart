import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/event.dart';
import 'format.dart';
import 'reminder_format.dart';

/// 일정 알림 (추가 AC): 일정마다 며칠 전(없음 · 2일 전 · 1일 전 · 당일) + 시각(1시간 단위).
/// - 정확한 알람 권한 없이 일반 예약 알림(inexactAllowWhileIdle) 사용 → 정각 전후 몇 분 차이 가능
/// - 재부팅 후 유지는 AndroidManifest의 ScheduledNotificationBootReceiver가 처리
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'event_reminder',
    '행사 알림',
    channelDescription: '일정마다 고른 날짜와 시간에 알려드려요',
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

  /// 알림 시각: 행사 [days]일 전 [hour]시 (기본 1일 전 오전 9시)
  static DateTime reminderTime(DateTime eventDate,
          {int days = Event.defaultReminderDays,
          int hour = Event.defaultReminderHour}) =>
      DateTime(eventDate.year, eventDate.month, eventDate.day - days, hour);

  /// 알림 제목: '내일 임원택 결혼식이에요' (2일 전 '모레', 당일 '오늘')
  static String reminderTitle(Event event) =>
      '${reminderWhenWord(event.reminderDays ?? 1)} ${event.title}이에요';

  /// 알림 내용: 날짜 · 장소
  static String reminderBody(Event event) {
    final place = (event.place ?? '').trim();
    return [formatDate(event.date), if (place.isNotEmpty) place].join(' · ');
  }

  /// 저장 · 수정할 때마다 부른다. 예전 예약을 지우고, 알림이 [없음]이거나 이미 지난 시각이면 다시 걸지 않는다.
  Future<void> scheduleForEvent(Event event) async {
    if (!_ready || event.id == null) return;
    await cancelForEvent(event.id!);
    final at = event.reminderAt;
    if (at == null) return;
    if (!at.isAfter(DateTime.now())) return; // 이미 지난 시각은 예약하지 않음

    await _plugin.zonedSchedule(
      id: event.id!,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: const NotificationDetails(android: _channel),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: reminderTitle(event),
      body: reminderBody(event),
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

  /// 테스트 메뉴: 1분 뒤 알림 (일정 알림과 같은 일반 예약이라 몇 분 늦을 수 있다)
  Future<void> showTest() async {
    if (!_ready) return;
    await _plugin.zonedSchedule(
      id: 999999,
      scheduledDate: tz.TZDateTime.from(
          DateTime.now().add(const Duration(minutes: 1)), tz.local),
      notificationDetails: const NotificationDetails(android: _channel),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: '알림 테스트',
      body: '일정 알림이 이렇게 보여요.',
    );
  }

  /// 테스트에서 휴대폰의 알림 허용 상태와 허용 창의 답을 흉내 낸다.
  @visibleForTesting
  static Future<bool> Function()? debugAreEnabled;
  @visibleForTesting
  static Future<bool> Function()? debugRequest;

  /// 알림이 허용되어 있는지. 확인할 수 없으면(테스트 등) 허용으로 본다.
  Future<bool> areEnabled() async {
    if (debugAreEnabled case final fake?) return fake();
    try {
      return await _android?.areNotificationsEnabled() ?? true;
    } catch (e) {
      debugPrint('알림 권한 확인 실패: $e');
      return true;
    }
  }

  /// 안드로이드의 알림 허용 창을 띄운다 (13 이상). 허용되면 true.
  Future<bool> requestPermission() async {
    if (debugRequest case final fake?) return fake();
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('알림 권한 요청 실패: $e');
      return false;
    }
  }
}
