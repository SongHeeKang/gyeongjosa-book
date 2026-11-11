import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../screens/paywall_screen.dart';
import '../services/limits.dart';
import '../services/pro_service.dart';
import '../theme/app_theme.dart';

/// 프로 결제 화면을 띄운다. 결제 후 프로가 되면 true.
Future<bool> showPaywall(BuildContext context, WidgetRef ref,
    {String? reason}) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => PaywallScreen(reason: reason),
  ));
  return ref.read(isProProvider);
}

/// 새 사람을 추가해도 되는지 확인 (31번째부터 결제 화면)
Future<bool> ensureCanAddPerson(BuildContext context, WidgetRef ref) async {
  if (ref.read(isProProvider)) return true;
  final count = await ref.read(repositoryProvider).countPeople();
  if (count < FreeLimits.people) return true;
  if (!context.mounted) return false;
  return showPaywall(context, ref,
      reason: '무료 버전은 ${FreeLimits.people}명까지 등록할 수 있어요.');
}

/// 내 행사를 새로 만들어도 되는지 확인 (두 번째부터 결제 화면)
Future<bool> ensureCanAddMyEvent(BuildContext context, WidgetRef ref) async {
  if (ref.read(isProProvider)) return true;
  final count = await ref.read(repositoryProvider).countMyEvents();
  if (count < FreeLimits.myEvents) return true;
  if (!context.mounted) return false;
  return showPaywall(context, ref,
      reason: '무료 버전은 내 행사를 ${FreeLimits.myEvents}개까지 만들 수 있어요.');
}

/// 프로 전용 기능(CSV, 상세 차트)을 눌렀을 때
Future<bool> ensurePro(BuildContext context, WidgetRef ref,
    {required String reason}) async {
  if (ref.read(isProProvider)) return true;
  return showPaywall(context, ref, reason: reason);
}

/// 작은 "PRO" 배지
class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text('PRO',
          style: TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
    );
  }
}
