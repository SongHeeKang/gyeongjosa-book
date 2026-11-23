import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/limits.dart';
import '../services/pro_service.dart';
import '../services/purchase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/common.dart';

/// 프로 결제 화면. 언제든 닫을 수 있다.
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key, this.reason});
  final String? reason;

  /// 프로 혜택 4줄 (추가 Y 확정). 엑셀 · 공유는 무료라 넣지 않는다.
  static const _benefits = [
    (Icons.people_outline, '사람을 제한 없이 등록해요', '무료는 ${FreeLimits.people}명까지'),
    (Icons.menu_book_outlined, '내 행사 장부를 여러 개 만들어요', '무료는 ${FreeLimits.myEvents}개'),
    (Icons.bar_chart, '관계별 · 연도별 상세 통계를 봐요', null),
    (Icons.verified_outlined, '한 번 결제로 평생 사용해요', null),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchase = ref.watch(purchaseProvider);

    // 결제가 끝나 프로가 되면 화면을 닫는다
    ref.listen(isProProvider, (prev, next) {
      if (next && prev != true && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    });
    ref.listen(purchaseProvider, (prev, next) {
      if (next.message != null && next.messageId != prev?.messageId) {
        showSnack(context, next.message!);
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: TestId('paywall_close', child: IconButton(
          tooltip: '닫기',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        )),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, 0, AppSpacing.page, AppSpacing.page),
          children: [
            const Text('경조사 장부 프로', style: AppText.appTitle),
            const SizedBox(height: 6),
            Text(reason ?? '많이 · 편하게 · 정리해서 보는 기능을 모두 열어요.',
                style: AppText.sub.copyWith(fontSize: 14)),
            const SizedBox(height: AppSpacing.section),
            const AppDivider(),
            const SizedBox(height: 8),
            for (final (icon, title, sub) in _benefits)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.item),
                child: Row(
                  children: [
                    Icon(icon, size: 24, color: AppColors.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppText.listName),
                          if (sub != null) ...[
                            const SizedBox(height: 2),
                            Text('($sub)', style: AppText.sub),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const AppDivider(),
            const SizedBox(height: AppSpacing.section),
            Text(purchase.priceText,
                textAlign: TextAlign.center,
                style: AppText.summaryAmount.copyWith(fontSize: 30)),
            const SizedBox(height: 4),
            Text('한 번 결제로 평생 사용',
                textAlign: TextAlign.center,
                style: AppText.listName.copyWith(color: AppColors.textSub)),
            const SizedBox(height: 2),
            const Text('구독 아님 · 광고 없음',
                textAlign: TextAlign.center, style: AppText.sub),
            const SizedBox(height: 24),
            TestId('paywall_buy', child: FilledButton(
              onPressed: purchase.busy
                  ? null
                  : () => ref.read(purchaseProvider.notifier).buy(),
              child: purchase.busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : Text('${purchase.priceText}에 프로 시작하기'),
            )),
            const SizedBox(height: 8),
            TestId('paywall_later', child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('나중에 할게요'),
            )),
            const SizedBox(height: 4),
            TestId('btn_restore_purchase', child: TextButton(
              onPressed: purchase.busy
                  ? null
                  : () => ref.read(purchaseProvider.notifier).restore(),
              child: const Text('이미 구매했어요 (구매 복원)'),
            )),
            const SizedBox(height: 8),
            const Text('이미 입력한 기록은 무료에서도 언제든 보고 · 고치고 · 지울 수 있어요.',
                textAlign: TextAlign.center, style: AppText.sub),
          ],
        ),
      ),
    );
  }
}
