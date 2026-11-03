import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/limits.dart';
import '../services/pro_service.dart';
import '../services/purchase_service.dart';
import '../widgets/common.dart';

/// 프로 결제 화면. 언제든 닫을 수 있다.
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key, this.reason});
  final String? reason;

  static const _benefits = [
    (Icons.people, '사람 무제한 등록', '무료는 ${FreeLimits.people}명까지'),
    (Icons.menu_book, '내 행사 장부 무제한', '결혼식 · 돌잔치 · 칠순 모두 따로'),
    (Icons.table_view, '엑셀(CSV) 내보내기', '전체 내역을 엑셀로 정리'),
    (Icons.bar_chart, '관계별 · 연도별 상세 차트', '어디에 얼마나 썼는지 한눈에'),
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
        leading: IconButton(
          iconSize: 30,
          tooltip: '닫기',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            const Icon(Icons.workspace_premium, size: 64, color: Color(0xFFB8860B)),
            const SizedBox(height: 8),
            Text('경조사 장부 프로',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            if (reason != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(reason!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ],
            const SizedBox(height: 20),
            for (final (icon, title, sub) in _benefits)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
                title: Text(title),
                subtitle: Text(sub),
              ),
            const SizedBox(height: 24),
            Text(purchase.priceText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
            const Text('한 번 결제로 평생 사용',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.black54)),
            const Text('구독 아님 · 광고 없음',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.black45)),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 60)),
              onPressed: purchase.busy
                  ? null
                  : () => ref.read(purchaseProvider.notifier).buy(),
              child: purchase.busy
                  ? const SizedBox(
                      width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                  : Text('${purchase.priceText}에 프로 시작하기'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('나중에 할게요'),
            ),
            TextButton(
              onPressed: purchase.busy
                  ? null
                  : () => ref.read(purchaseProvider.notifier).restore(),
              child: const Text('이미 구매했어요 (구매 복원)'),
            ),
            const SizedBox(height: 8),
            const Text('이미 입력한 기록은 무료에서도 언제든 보고 · 고치고 · 지울 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black45)),
          ],
        ),
      ),
    );
  }
}
