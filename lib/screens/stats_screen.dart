import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../services/format.dart';
import '../services/pro_service.dart';
import '../widgets/common.dart';
import '../widgets/pro_gate.dart';

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
      appBar: AppBar(title: const Text('통계')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 32,
                onPressed: years.first < _year ? () => setState(() => _year--) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$_year년', style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                iconSize: 32,
                onPressed: _year < years.last ? () => setState(() => _year++) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          AsyncBody(
            value: monthly,
            builder: (rows) {
              final sent = rows.fold(0, (s, r) => s + r.sent);
              final received = rows.fold(0, (s, r) => s + r.received);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: [
                      TotalTile(label: '보낸 돈', amount: sent, color: sentColor),
                      TotalTile(label: '받은 돈', amount: received, color: receivedColor),
                    ]),
                  ),
                  const SectionTitle('월별 보냄 · 받음', trailing: _Legend()),
                  _ChartCard(
                    child: _GroupedBarChart(
                      labels: [for (final r in rows) '${r.month}'],
                      sent: [for (final r in rows) r.sent],
                      received: [for (final r in rows) r.received],
                      labelSuffix: '월',
                    ),
                  ),
                ],
              );
            },
          ),
          SectionTitle('관계별 ($_year년)',
              trailing: isPro ? null : const ProBadge()),
          if (isPro)
            AsyncBody(
              value: ref.watch(relationTotalsProvider(_year)),
              builder: (rows) {
                final byRel = {for (final r in rows) r.relation: r};
                return _ChartCard(
                  child: _GroupedBarChart(
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
            const _LockedChart(
                message: '가족 · 친구 · 회사별로\n얼마나 주고받았는지 한눈에 봐요'),
          SectionTitle('연도별', trailing: isPro ? null : const ProBadge()),
          if (isPro)
            AsyncBody(
              value: ref.watch(yearlyTotalsProvider),
              builder: (rows) => rows.isEmpty
                  ? const EmptyView(icon: Icons.bar_chart, message: '아직 기록이 없어요.')
                  : _ChartCard(
                      child: _GroupedBarChart(
                        labels: [for (final r in rows) '${r.year}'],
                        sent: [for (final r in rows) r.sent],
                        received: [for (final r in rows) r.received],
                      ),
                    ),
            )
          else
            const _LockedChart(message: '해마다 경조사비가 얼마나 나갔는지\n흐름을 볼 수 있어요'),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 12, color: c),
          const SizedBox(width: 4),
          Text(t, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 12),
        ]);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      dot(sentColor, '보냄'),
      dot(receivedColor, '받음'),
    ]);
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
          child: SizedBox(height: 240, child: child),
        ),
      );
}

/// 프로가 아닐 때 보여주는 잠긴 차트 자리
class _LockedChart extends ConsumerWidget {
  const _LockedChart({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => ensurePro(context, ref,
            reason: '관계별 · 연도별 상세 차트는 프로 기능이에요.'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Column(
            children: [
              const Icon(Icons.lock_outline, size: 40, color: Colors.black45),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17)),
              const SizedBox(height: 12),
              const Text('눌러서 프로로 열기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 눈금 간격을 1 · 2 · 5 × 10ⁿ 원(최소 1만 원)으로 맞춘다.
double _niceInterval(num raw) {
  var step = 10000.0;
  while (true) {
    for (final m in [1, 2, 5]) {
      if (step * m >= raw) return step * m;
    }
    step *= 10;
  }
}

/// 보냄/받음 두 막대씩 묶인 그래프
class _GroupedBarChart extends StatelessWidget {
  const _GroupedBarChart({
    required this.labels,
    required this.sent,
    required this.received,
    this.labelSuffix = '',
  });
  final List<String> labels;
  final List<int> sent;
  final List<int> received;
  final String labelSuffix;

  @override
  Widget build(BuildContext context) {
    final maxValue = [...sent, ...received].fold(0, math.max);
    final interval = _niceInterval(maxValue == 0 ? 100000 : maxValue / 4);
    final maxY = maxValue == 0
        ? interval * 4
        : ((maxValue / interval).floor() + 1) * interval;
    final barWidth = labels.length > 8 ? 7.0 : 14.0;

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: interval,
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.black87,
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${labels[groupIndex]}$labelSuffix ${rodIndex == 0 ? '보냄' : '받음'}\n${formatWon(rod.toY.round())}',
              const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: interval,
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(
                  meta: meta,
                  child: Text(value == 0 ? '0' : '${formatNumber((value / 10000).round())}만',
                      style: const TextStyle(fontSize: 13)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(labels[i], style: const TextStyle(fontSize: 14)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < labels.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 2,
              barRods: [
                BarChartRodData(
                    toY: sent[i].toDouble(),
                    color: sentColor,
                    width: barWidth,
                    borderRadius: BorderRadius.circular(2)),
                BarChartRodData(
                    toY: received[i].toDouble(),
                    color: receivedColor,
                    width: barWidth,
                    borderRadius: BorderRadius.circular(2)),
              ],
            ),
        ],
      ),
    );
  }
}
