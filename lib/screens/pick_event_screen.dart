import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/event.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/test_id.dart';
import 'event_routes.dart';

/// 받은 돈 적기에서 고를 수 있는 행사 하나 (내 행사 또는 다른 사람 행사)
class PickableEvent {
  const PickableEvent.mine(this.mine) : other = null;
  const PickableEvent.other(this.other) : mine = null;
  final EventSummary? mine;
  final ReceptionSummary? other;

  bool get isMine => mine != null;
  String get title => mine?.event.title ?? other!.reception.title;
  DateTime get date => mine?.event.date ?? other!.reception.date;
  int get count => mine?.count ?? other!.count;
  int get total => mine?.total ?? other!.total;

  /// 같은 날이면 나중에 만든 것이 앞
  DateTime get _createdAt => other?.reception.startedAt ?? date;
}

/// 내 행사 + 다른 사람 행사, 최근 순
List<PickableEvent> pickableEvents(
    List<EventSummary> events, List<ReceptionSummary> receptions) {
  final list = [
    for (final s in events)
      if (s.event.isMine) PickableEvent.mine(s),
    for (final r in receptions) PickableEvent.other(r),
  ];
  list.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : b._createdAt.compareTo(a._createdAt);
  });
  return list;
}

/// 기록하기 > [받은 돈 적기]: '어느 행사에 적을까요?'
/// 행사마다 '내 행사' / '다른 사람 행사'가 표시되고, 맨 아래 [+ 새 행사 만들기].
/// 행사가 하나도 없으면 이 화면 대신 바로 행사 만들기 화면이 열린다([openReceiveMoney]).
class PickEventScreen extends ConsumerWidget {
  const PickEventScreen({super.key});

  /// 고른 행사의 받은 돈 적기. 뒤로 가면 이 목록으로 돌아온다.
  static Future<void> open(
      BuildContext context, WidgetRef ref, PickableEvent item) async {
    if (item.mine case final s?) {
      await Navigator.push(context, myEventReceiveRoute(s.event));
      return;
    }
    final r = item.other!.reception;
    // 받기를 끝낸 행사도 여기서 고르면 이어서 받는다
    if (r.isFinished) {
      await ref.read(repositoryProvider).setReceptionFinished(r.id, finished: false);
      ref.refreshData();
    }
    if (!context.mounted) return;
    await Navigator.push(context, receptionReceiveRoute(r.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventSummariesProvider);
    final receptions =
        ref.watch(receptionSummariesProvider).value ?? const <ReceptionSummary>[];
    return Scaffold(
      appBar: AppBar(title: const Text('받은 돈 적기')),
      body: AsyncBody(
        value: events,
        builder: (all) {
          final items = pickableEvents(all, receptions);
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.page, 8, AppSpacing.page, 12),
                child: Text('어느 행사에 적을까요?', style: AppText.appTitle),
              ),
              for (final item in items)
                TestId('pick_event_${item.title}',
                    child: LedgerEventTile(
                      title: item.title,
                      isMine: item.isMine,
                      subtitle:
                          '${formatDate(item.date)} · ${item.count}명 · ${formatWon(item.total)}',
                      onTap: () => open(context, ref, item),
                    )),
              const AppDivider(),
              TestId('btn_pick_new_event',
                  child: InkWell(
                    onTap: () => openCreateEvent(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.page, vertical: 18),
                      child: Row(
                        children: [
                          const Icon(Icons.add, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('새 행사 만들기',
                                style: AppText.listName
                                    .copyWith(color: AppColors.primary)),
                          ),
                        ],
                      ),
                    ),
                  )),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

/// 기록하기 > [받은 돈 적기]. 행사가 하나도 없으면 바로 만들기 화면, 있으면 고르는 목록.
Future<void> openReceiveMoney(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  final hasMine = (await repo.myEvents()).isNotEmpty;
  final hasOther = hasMine ? true : (await repo.receptionSummaries()).isNotEmpty;
  if (!context.mounted) return;
  if (!hasMine && !hasOther) return openCreateEvent(context);
  await Navigator.push(context,
      MaterialPageRoute<void>(builder: (_) => const PickEventScreen()));
}

/// 행사 한 줄: 제목 + '내 행사' / '다른 사람 행사' 표시 + 날짜 · 인원 · 금액
class LedgerEventTile extends StatelessWidget {
  const LedgerEventTile({
    super.key,
    required this.title,
    required this.isMine,
    required this.subtitle,
    this.subtitleHighlight = false,
    this.showKind = true,
    this.onTap,
  });
  final String title;
  final bool isMine;
  final String subtitle;

  /// 받는 중인 다른 사람 행사처럼 눈에 띄게 할 때
  final bool subtitleHighlight;

  /// 이미 묶음 제목으로 종류가 보이면 끈다
  final bool showKind;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page, vertical: AppSpacing.item),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showKind) ...[
                    EventKindLabel(isMine: isMine),
                    const SizedBox(height: 4),
                  ],
                  Text(title,
                      style: AppText.listName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: AppText.sub.copyWith(
                          color: subtitleHighlight ? AppColors.primary : null),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.divider),
          ],
        ),
      ),
    );
  }
}

/// '내 행사' / '다른 사람 행사' 작은 표시
class EventKindLabel extends StatelessWidget {
  const EventKindLabel({super.key, required this.isMine});
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isMine ? AppColors.primarySoft : AppColors.background,
        border: Border.all(color: isMine ? AppColors.primarySoft : AppColors.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(isMine ? '내 행사' : '다른 사람 행사',
          style: AppText.sub.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isMine ? AppColors.primary : AppColors.textSub)),
    );
  }
}

