import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../theme/app_theme.dart';
import 'test_id.dart';

/// 홈 요약 카드 제목 (추가 AE): '2026년 나의 경조사' / '전체 기간 나의 경조사'
String periodTitle(int? year) =>
    year == null ? '전체 기간 나의 경조사' : '$year년 나의 경조사';

/// '전체 기간 · 2024~2026' (한 해뿐이면 '2026')
String allPeriodLabel(List<int> years) {
  if (years.isEmpty) return '전체 기간 · ${DateTime.now().year}';
  final first = years.reduce((a, b) => a < b ? a : b);
  final last = years.reduce((a, b) => a > b ? a : b);
  return first == last ? '전체 기간 · $first' : '전체 기간 · $first~$last';
}

/// 아래에서 올라오는 '어느 기간을 볼까요?' (오른쪽 위 X, 바깥 누르기 · 뒤로 가기로도 닫힘).
/// 고르면 [homePeriodProvider]만 바뀐다(요약 카드만 그 기간 합계로).
Future<void> showPeriodSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const _PeriodSheet(),
    );

class _PeriodSheet extends ConsumerWidget {
  const _PeriodSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(homePeriodProvider);
    final years = ref.watch(recordYearCountsProvider).value ??
        [(year: DateTime.now().year, count: 0)];

    Widget row(String id, String label, int? year) {
      final on = selected == year;
      return TestId(
        id,
        selected: on,
        child: ListTile(
          minTileHeight: 56,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          title: Text(label,
              style: AppText.listName.copyWith(
                  color: on ? AppColors.primary : AppColors.text,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
          trailing: on ? const Icon(Icons.check, color: AppColors.primary) : null,
          onTap: () {
            ref.read(homePeriodProvider.notifier).select(year);
            Navigator.pop(context);
          },
        ),
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, 12, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                      child: Text('어느 기간을 볼까요?', style: AppText.appTitle)),
                  TestId('period_close', child: IconButton(
                    tooltip: '닫기',
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: () => Navigator.pop(context),
                    icon: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                          color: AppColors.closeCircle, shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          size: 20, color: AppColors.icon),
                    ),
                  )),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  row('period_all',
                      allPeriodLabel([for (final y in years) y.year]), null),
                  for (final y in years)
                    row('period_${y.year}', '${y.year}년 · ${y.count}건', y.year),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
