import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../models/reception.dart';
import '../services/notification_service.dart';
import '../widgets/common.dart';
import 'reception_form_screen.dart';

/// 행사 상세 [수정]: 내 행사를 '행사 수정' 화면으로 연다. 구분별 손님 수를 함께 넘긴다.
Future<void> openEditMyEvent(
    BuildContext context, Event event, List<GiftRecord> received) {
  final counts = <String, int>{};
  for (final r in received) {
    final side = r.side ?? ReceptionDefaults.noSide;
    counts[side] = (counts[side] ?? 0) + 1;
  }
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ReceptionFormScreen.edit(
        editEvent: event,
        sideCounts: counts,
        guestCount: received.length,
      ),
    ),
  );
}

/// 다른 사람 행사 상세 [수정]
Future<void> openEditReception(BuildContext context, ReceptionPackage package) {
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ReceptionFormScreen.edit(
        editReception: package.reception,
        sideCounts: {
          for (final side in package.sides)
            side: package.totalsFor(side).count,
        },
        guestCount: package.totals.count,
      ),
    ),
  );
}

/// 마지막 확인: "정말 지울까요?"
Future<bool> _confirmAgain(BuildContext context) => confirmDialog(
      context,
      title: '정말 지울까요?',
      message: '되돌릴 수 없어요.',
      okText: '지우기',
      destructive: true,
    );

/// 내 행사 삭제(두 번 확인). 지금 동작 그대로: 행사만 지우고, 이 행사로 적은 받음 기록은
/// 사람 탭 · 통계에 남는다(행사 연결만 끊긴다). 지웠으면 true.
Future<bool> deleteMyEventWithConfirm(
    BuildContext context, WidgetRef ref, Event event, int guestCount) async {
  final ok = await confirmDialog(
    context,
    title: '이 행사를 지울까요?',
    message: guestCount > 0
        ? '받은 손님 $guestCount명의 기록은 사람 탭 · 통계에 그대로 남아요.'
        : null,
    okText: '지우기',
    destructive: true,
  );
  if (!ok || !context.mounted || !await _confirmAgain(context)) return false;
  await NotificationService.instance.cancelForEvent(event.id!);
  await ref.read(repositoryProvider).deleteEvent(event.id!);
  ref.refreshData();
  return true;
}

/// 다른 사람 행사 삭제(두 번 확인): 받은 명단이 모두 지워진다. 지웠으면 true.
Future<bool> deleteReceptionWithConfirm(BuildContext context, WidgetRef ref,
    String receptionId, int guestCount) async {
  final ok = await confirmDialog(
    context,
    title: '이 행사와 손님 $guestCount명을 지울까요?',
    message: '받은 명단이 모두 지워져요. 내 사람 탭 · 통계에는 영향이 없어요.',
    okText: '지우기',
    destructive: true,
  );
  if (!ok || !context.mounted || !await _confirmAgain(context)) return false;
  await ref.read(repositoryProvider).deleteReception(receptionId);
  ref.refreshData();
  return true;
}

/// 삭제 뒤: 첫 화면까지 닫고 행사 탭을 보여준다.
void goToEventList(BuildContext context, WidgetRef ref) {
  ref.read(tabRequestProvider.notifier).go(AppTabs.events);
  Navigator.of(context).popUntil((route) => route.isFirst);
}
