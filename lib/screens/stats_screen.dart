import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../services/pro_service.dart';
import '../services/limit_service.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/coach_mark.dart';
import '../widgets/grouped_bar_chart.dart';
import '../widgets/common.dart';
import '../widgets/pro_gate.dart';
import '../widgets/screen_coach.dart';
import '../widgets/settings_button.dart';


/// 통계 탭: 월별 막대그래프(무료) + 관계별 · 연도별 차트(프로)
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final years = ref.watch(recordYearsProvider).value ?? [_year];
    final monthly = ref.watch(monthlyTotalsProvider(_year));
    final isPro = ref.watch(isProProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('통계'),
        actions: const [
          HelpButton(screen: CoachScreen.stats),
          SettingsButton(),
          SettingsButton.trailingGap,
        ],
      ),
      body: ListView(
        // 맨 아래 내용이 떠 있는 [기록하기] 버튼에 가리지 않게
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Center(
            child: CoachTarget(
              spot: CoachSpot.statsPeriod,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    iconSize: 28,
                    onPressed:
                        years.first < _year ? () => setState(() => _year--) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('$_year년', style: AppText.appTitle),
                  IconButton(
                    iconSize: 28,
                    onPressed:
                        _year < years.last ? () => setState(() => _year++) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
          AsyncBody(
            value: monthly,
            builder: (rows) {
              final sent = rows.fold(0, (s, r) => s + r.sent);
              final received = rows.fold(0, (s, r) => s + r.received);
              return Column(
                children: [
                  const SizedBox(height: 8),
                  TestId('stats_summary', child: SummaryRow(
                      sent: sent,
                      received: received,
                      sentLabel: '보낸 돈',
                      receivedLabel: '받은 돈')),
                  const SizedBox(height: AppSpacing.section),
                  const AppDivider(),
                  const SectionTitle('월별 보냄 · 받음', trailing: SentReceivedLegend()),
                  CoachTarget(
                    spot: CoachSpot.statsChart,
                    child: TestId('stats_monthly_chart', child: _ChartCard(
                      child: GroupedBarChart(
                        labels: [for (final r in rows) '${r.month}'],
                        sent: [for (final r in rows) r.sent],
                        received: [for (final r in rows) r.received],
                        labelSuffix: '월',
                      ),
                    )),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.section),
          const AppDivider(),
          SectionTitle('관계별 ($_year년)',
              trailing: isPro ? null : const ProBadge()),
          if (isPro)
            AsyncBody(
              value: ref.watch(relationTotalsProvider(_year)),
              builder: (rows) {
                final byRel = {for (final r in rows) r.relation: r};
                return _ChartCard(
                  child: GroupedBarChart(
                    labels: Relations.all,
                    sent: [for (final r in Relations.all) byRel[r]?.sent ?? 0],
                    received: [
                      for (final r in Relations.all) byRel[r]?.received ?? 0
                    ],
                  ),
                );
              },
            )
          else
            TestId('stats_detail_relation', child: const _LockedChart(
                message: '가족 · 친구 · 회사별로\n얼마나 주고받았는지 한눈에 봐요')),
          const SizedBox(height: AppSpacing.section),
          const AppDivider(),
          SectionTitle('연도별', trailing: isPro ? null : const ProBadge()),
          if (isPro)
            AsyncBody(
              value: ref.watch(yearlyTotalsProvider),
              builder: (rows) => rows.isEmpty
                  ? const EmptyView(icon: Icons.bar_chart, message: '아직 기록이 없어요.')
                  : _ChartCard(
                      child: GroupedBarChart(
                        labels: [for (final r in rows) '${r.year}'],
                        sent: [for (final r in rows) r.sent],
                        received: [for (final r in rows) r.received],
                      ),
                    ),
            )
          else
            TestId('stats_detail_yearly', child: const _LockedChart(message: '해마다 경조사비가 얼마나 나갔는지\n흐름을 볼 수 있어요')),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page - 12, 12, AppSpacing.page, 0),
        child: SizedBox(height: 220, child: child),
      );
}

/// 프로가 아닐 때 보여주는 잠긴 차트 자리
class _LockedChart extends ConsumerWidget {
  const _LockedChart({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 0),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        ),
        onPressed: () => LimitService.canUseProFeature(context, ref,
            reason: '관계별 · 연도별 상세 차트는 프로 기능이에요.'),
        child: Column(
          children: [
            const Icon(Icons.lock_outline, size: 28, color: AppColors.icon),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: AppText.sub.copyWith(height: 1.5)),
            const SizedBox(height: 8),
            Text('눌러서 프로로 열기',
                style: AppText.link.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

