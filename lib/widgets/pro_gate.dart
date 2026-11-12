import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/paywall_screen.dart';
import '../services/pro_service.dart';
import '../theme/app_theme.dart';
import 'test_id.dart';

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

/// 내 행사 한도에 닿은 '새로 만들기' 옆의 자물쇠 · 프로 표시.
/// [compact]면 자물쇠만 (글자를 크게 키운 좁은 폰의 제목줄처럼 자리가 없을 때).
class ProLockMark extends StatelessWidget {
  const ProLockMark({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TestId('pro_lock',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 18, color: AppColors.primary),
          if (!compact) ...const [
            SizedBox(width: 2),
            Text('프로',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}
