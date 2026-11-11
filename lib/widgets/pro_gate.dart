import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/paywall_screen.dart';
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
