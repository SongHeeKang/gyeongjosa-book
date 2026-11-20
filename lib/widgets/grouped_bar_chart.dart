import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/format.dart';
import '../theme/app_theme.dart';

/// 통계 탭 '월별 보냄 · 받음'과 홈 '최근 6개월'이 같이 쓰는 그래프.
/// 막대 색: 보냄 = [AppColors.sent](코랄), 받음 = [AppColors.received](파랑)
/// 보냄/받음 두 막대씩 묶인 그래프
class GroupedBarChart extends StatelessWidget {
  const GroupedBarChart({
    super.key,
    required this.labels,
    required this.sent,
    required this.received,
    this.labelSuffix = '',
    this.compact = false,
  });
  final List<String> labels;
  final List<int> sent;
  final List<int> received;
  final String labelSuffix;

  /// 홈 '최근 6개월'처럼 작게: 왼쪽 눈금 글자를 줄이고 막대 사이를 좁힌다
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final maxValue = [...sent, ...received].fold(0, math.max);
    final interval = _niceInterval(maxValue == 0 ? 100000 : maxValue / 4);
    final maxY = maxValue == 0
        ? interval * 4
        : ((maxValue / interval).floor() + 1) * interval;
    final barWidth = labels.length > 8 ? 7.0 : (compact ? 10.0 : 14.0);

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.divider, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.text,
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${labels[groupIndex]}$labelSuffix ${rodIndex == 0 ? '보냄' : '받음'}\n${formatWon(rod.toY.round())}',
              const TextStyle(
                  fontFamily: AppText.fontFamily, color: Colors.white, fontSize: 13),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: compact ? 40 : 48,
              interval: interval,
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(
                  meta: meta,
                  child: Text(value == 0 ? '0' : '${formatNumber((value / 10000).round())}만',
                      style: AppText.sub.copyWith(fontSize: 11)),
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
                  child: Text(labels[i], style: AppText.sub.copyWith(fontSize: 12)),
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
                    color: AppColors.sent,
                    width: barWidth,
                    borderRadius: BorderRadius.circular(2)),
                BarChartRodData(
                    toY: received[i].toDouble(),
                    color: AppColors.received,
                    width: barWidth,
                    borderRadius: BorderRadius.circular(2)),
              ],
            ),
        ],
      ),
    );
  }
}

/// 작은 범례: ■ 보냄 ■ 받음
class SentReceivedLegend extends StatelessWidget {
  const SentReceivedLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(t, style: AppText.sub),
          const SizedBox(width: 8),
        ]);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      dot(AppColors.sent, '보냄'),
      dot(AppColors.received, '받음'),
    ]);
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

