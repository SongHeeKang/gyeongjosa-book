import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../services/limit_service.dart';
import '../services/receive_targets.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/common.dart';
import '../widgets/pro_gate.dart';
import '../widgets/reception_entry_sheet.dart';
import 'event_detail_screen.dart';
import 'receive_money_screen.dart';
import '../widgets/share_download.dart';

/// 다른 사람 행사 상세 (받기 끝내기 화면도 이것): 구분별 요약,
/// [이어서 받기] [장부 보내기] [내 행사로 바꾸기]
class ReceptionSummaryScreen extends ConsumerWidget {
  const ReceptionSummaryScreen({super.key, required this.receptionId});
  final String receptionId;

  /// 잘못 고른 다른 사람 행사를 내 행사로 바꾼다. 누르는 순간 내 행사 한도와 사람 한도를 본다.
  /// 한도에 걸려 결제하지 않으면 바꾸지 않는다(일부만 바꾸지 않음).
  Future<void> _convert(BuildContext context, WidgetRef ref,
      ReceptionPackage package) async {
    // 빠르게 두 번 눌러도 한 번만 (두 번째 내 행사가 생기지 않게)
    if (_converting) return;
    _converting = true;
    try {
      await _convertOnce(context, ref, package);
    } finally {
      _converting = false;
    }
  }

  static bool _converting = false;

  Future<void> _convertOnce(BuildContext context, WidgetRef ref,
      ReceptionPackage package) async {
    if (!await LimitService.canCreateMyEvent(context, ref)) return;
    if (!context.mounted) return;
    final repo = ref.read(repositoryProvider);
    final limit = LimitService.importPeopleLimit(ref);
    if (limit != null) {
      final plan = await repo.planImport(package, maxPeople: limit);
      if (!context.mounted) return;
      if (plan.skippedByLimit > 0 &&
          !await showPaywall(context, ref,
              reason:
                  '${plan.remaining}명 중 ${plan.items.length}명까지 바꿀 수 있어요. 모두 바꾸려면 프로가 필요해요.')) {
        return;
      }
    }
    if (!context.mounted) return;
    final ok = await confirmDialog(context,
        title: '내 행사로 바꿀까요?',
        message:
            '손님 ${package.totals.count}명이 사람 탭에도 들어가요. 바꾼 뒤에는 행사 탭의 내 행사에서 볼 수 있어요.',
        okText: '바꾸기');
    if (!ok || !context.mounted) return;
    final r = package.reception;
    // 저장 순간 안전장치: 한도를 넘으면 바꾸지 않고 결제 화면
    final result = await LimitService.saveMyEvent(context, ref, (max) => repo.applyImport(
      package,
      maxMyEvents: max,
      newEvent: Event(
        type: EventTypes.all.contains(r.eventType) ? r.eventType : '기타',
        title: r.title.isEmpty ? '받은 장부' : r.title,
        date: r.date,
        isMine: true,
        notify: false,
        receiveSides: r.sides,
        mealTicketEnabled: r.mealTicketEnabled,
        defaultMealTickets: r.defaultMealTickets,
        methodEnabled: r.methodEnabled,
      ),
      removeReception: true,
    ));
    if (result == null) return;
    ref.refreshData();
    if (!context.mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
            builder: (_) => EventDetailScreen(eventId: result.eventId)));
  }

  Future<void> _reopen(BuildContext context, WidgetRef ref) async {
    await ref
        .read(repositoryProvider)
        .setReceptionFinished(receptionId, finished: false);
    ref.refreshData();
    if (!context.mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
            builder: (_) =>
                ReceiveMoneyScreen(target: ReceptionTarget(receptionId))));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(context,
        title: '다른 사람 행사 삭제',
        message: '받은 명단이 모두 지워져요. 내 사람 탭 · 통계에는 영향이 없어요.\n삭제할까요?',
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
              body: const Center(child: Text('삭제된 장부예요.')));
        }
        final r = package.reception;
        final totals = package.totals;
        return Scaffold(
          appBar: AppBar(
            title: const Text('다른 사람 행사'),
            actions: [
              // [공유] [다운로드]: 이 행사 하나. 받은 사람이 없으면 회색
              ShareDownloadButtons(
                enabled: totals.count > 0,
                target: () => ReceptionExport(ref, package: package),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.icon),
                onSelected: (v) {
                  if (v == 'delete') _delete(context, ref);
                },
                itemBuilder: (_) => const [
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
                        [
                          r.eventType,
                          formatDate(r.date),
                          if (r.operatorName.isNotEmpty) '받은 사람 ${r.operatorName}',
                        ].join(' · '),
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
                      child: TestId('btn_continue_receive', child: OutlinedButton.icon(
                        onPressed: () => _reopen(context, ref),
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('이어서 받기'),
                      )),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: AppSpacing.receptionButton,
                      child: TestId('btn_send', child: FilledButton.icon(
                        onPressed: totals.count == 0
                            ? null
                            : () => showExportSheet(context,
                                mode: ExportMode.share,
                                target: ReceptionExport(ref, package: package)),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('공유하기'),
                      )),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: AppSpacing.receptionButton,
                      child: TestId('btn_move_to_mine', child: OutlinedButton.icon(
                        // 예전 버전에서 이미 옮긴 장부는 다시 바꾸지 않는다
                        onPressed: r.imported
                            ? null
                            : () => _convert(context, ref, package),
                        icon: Icon(r.imported ? Icons.check : Icons.swap_horiz),
                        label: Text(r.imported ? '내 행사로 옮겼어요' : '내 행사로 바꾸기'),
                      )),
                    ),
                    if (!r.imported) ...[
                      const SizedBox(height: 4),
                      const Text('내 행사인데 잘못 골랐다면 눌러 주세요.',
                          textAlign: TextAlign.center, style: AppText.sub),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              const AppDivider(),
              SectionTitle('받은 명단 ${totals.count}명'),
              if (package.entries.isEmpty)
                const EmptyView(
                    icon: Icons.list_alt, message: '아직 받은 사람이 없어요.')
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
