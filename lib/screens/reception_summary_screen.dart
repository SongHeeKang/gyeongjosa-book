import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/common.dart';
import '../widgets/reception_entry_sheet.dart';
import 'reception_import_screen.dart';
import 'reception_screen.dart';
import 'reception_send_screen.dart';

/// 접수 마치기: 구분별 요약, 장부 보내기, 내 장부로 옮기기
class ReceptionSummaryScreen extends ConsumerWidget {
  const ReceptionSummaryScreen({super.key, required this.receptionId});
  final String receptionId;

  /// 장부 보내기: 받는 사람에게 무엇이 보이는지 보여주는 화면에서 고른다.
  Future<void> _share(BuildContext context, ReceptionPackage package) =>
      Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => ReceptionSendScreen(package: package)));

  Future<void> _reopen(BuildContext context, WidgetRef ref) async {
    await ref
        .read(repositoryProvider)
        .setReceptionFinished(receptionId, finished: false);
    ref.refreshData();
    if (!context.mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
            builder: (_) => ReceptionScreen(receptionId: receptionId)));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(context,
        title: '접수 장부 삭제',
        message: '접수 명단이 모두 지워져요. 내 장부로 옮긴 내역은 그대로 남아요.\n삭제할까요?',
        okText: '삭제',
        destructive: true);
    if (!ok) return;
    await ref.read(repositoryProvider).deleteReception(receptionId);
    ref.refreshData();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody(
      value: ref.watch(receptionPackageProvider(receptionId)),
      builder: (package) {
        if (package == null) {
          return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('삭제된 접수 장부예요.')));
        }
        final r = package.reception;
        final totals = package.totals;
        return Scaffold(
          appBar: AppBar(
            title: const Text('접수 요약'),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.icon),
                onSelected: (v) {
                  if (v == 'reopen') _reopen(context, ref);
                  if (v == 'delete') _delete(context, ref);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'reopen', child: Text('접수 다시 열기')),
                  PopupMenuItem(value: 'delete', child: Text('삭제')),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(r.title, style: AppText.sectionTitle),
                    const SizedBox(height: 4),
                    Text(
                        '${r.eventType} · ${formatDate(r.date)} · 접수 ${r.operatorName}',
                        style: AppText.sub),
                    const SizedBox(height: 16),
                    TestId('summary_total', child: Text('${totals.count}명 · ${formatWon(totals.amount)}',
                        style: AppText.summaryAmount
                            .copyWith(color: AppColors.primary))),
                    const SizedBox(height: 2),
                    TestId('summary_meal_total', child: Text(
                        package.showsMealTickets
                            ? '식권 ${totals.mealTickets}매 · 봉투 금액과 맞춰 보세요'
                            : '봉투 금액과 맞춰 보세요',
                        style: AppText.sub)),
                    if (r.methodEnabled) ...[
                      const SizedBox(height: 2),
                      Text(
                          [
                            for (final method in const [
                              ReceptionDefaults.cash,
                              ReceptionDefaults.transfer,
                            ])
                              '${ReceptionDefaults.methodLabel(method)} ${formatWon(package.totalsForMethod(method).amount)}',
                          ].join(' · '),
                          style: AppText.sub),
                    ],
                    if (package.sides.length > 1) ...[
                      const SizedBox(height: 12),
                      for (final side in package.sides)
                        _sideRow(side, package.totalsFor(side),
                            showMeals: package.showsMealTickets),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: AppSpacing.receptionButton,
                      child: TestId('btn_send', child: FilledButton.icon(
                        onPressed: totals.count == 0
                            ? null
                            : () => _share(context, package),
                        icon: const Icon(Icons.send),
                        label: const Text('장부 보내기'),
                      )),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: AppSpacing.receptionButton,
                      child: TestId('btn_move_to_mine', child: OutlinedButton.icon(
                        onPressed: totals.count == 0
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                    builder: (_) => ReceptionImportScreen(
                                        package: package))),
                        icon: Icon(r.imported ? Icons.check : Icons.move_to_inbox),
                        label: Text(r.imported ? '내 장부로 옮겼어요' : '내 장부로 옮기기'),
                      )),
                    ),
                    if (!r.imported) ...[
                      const SizedBox(height: 4),
                      const Text('혼주 · 상주 본인 폰으로 접수했다면 눌러 주세요.',
                          textAlign: TextAlign.center, style: AppText.sub),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              const AppDivider(),
              SectionTitle('접수 명단 ${totals.count}명'),
              if (package.entries.isEmpty)
                const EmptyView(
                    icon: Icons.list_alt, message: '아직 접수한 사람이 없어요.')
              else
                for (final e in package.entries)
                  ReceptionEntryTile(
                    entry: e,
                    reception: r,
                    onTap: () => showReceptionEntryForm(context,
                        entry: e, sides: package.sides),
                  ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _sideRow(String side, ReceptionTotals t, {required bool showMeals}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        // 좁은 폰에서는 인원 · 금액이 다음 줄로 내려가게 한다
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 2,
          children: [
            Text(side == ReceptionDefaults.noSide ? '구분 없음' : side,
                style: AppText.listName),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: showMeals
                        ? '${t.count}명 · 식권 ${t.mealTickets}매 · '
                        : '${t.count}명 · ',
                    style: AppText.sub),
                TextSpan(text: formatWon(t.amount), style: AppText.listAmount),
              ]),
            ),
          ],
        ),
      );
}
