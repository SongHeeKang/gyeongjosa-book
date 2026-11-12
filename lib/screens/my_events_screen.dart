import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../services/limit_service.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/common.dart';
import '../widgets/coach_mark.dart';
import '../widgets/pro_gate.dart';
import '../widgets/screen_coach.dart';
import '../widgets/settings_button.dart';
import 'event_detail_screen.dart';
import 'reception_summary_screen.dart';
import 'whose_event_screen.dart';

/// 내 행사 탭: '내 행사'와 '대신 받은 장부' 두 묶음. 남의 행사는 홈의 일정으로 간다.
class MyEventsScreen extends ConsumerWidget {
  const MyEventsScreen({super.key});

  /// 누르는 순간 한도 검사 (닿았으면 바로 결제 화면)
  Future<void> _create(BuildContext context, WidgetRef ref) =>
      createMyEvent(context, ref);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventSummariesProvider);
    final receptions =
        ref.watch(receptionSummariesProvider).value ?? const <ReceptionSummary>[];
    final hasMine =
        events.value?.any((s) => s.event.isMine) ?? false;
    final locked = ref.watch(myEventLimitReachedProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 행사'),
        actions: [
          // 비어 있을 때는 화면 가운데 버튼 하나만 보여준다
          if (hasMine) ...[
            CoachTarget(
              spot: CoachSpot.myEventsCreate,
              child: TestId('btn_new_event', child: TextButton(
                onPressed: () => _create(context, ref),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('내 행사 만들기'),
                    if (locked) ...[
                      const SizedBox(width: 4),
                      ProLockMark(compact: isNarrowScreen(context)),
                    ],
                  ],
                ),
              )),
            ),
          ],
          const HelpButton(screen: CoachScreen.myEvents),
          const SettingsButton(),
          SettingsButton.trailingGap,
        ],
      ),
      body: AsyncBody(
        value: events,
        builder: (all) {
          final mine = all.where((s) => s.event.isMine).toList();
          return ListView(
            children: [
              if (mine.isEmpty)
                EmptyView(
                  icon: Icons.celebration_outlined,
                  message: '결혼식 · 돌잔치처럼 내가 받는 행사를 만들어 보세요',
                  action: CoachTarget(
                    spot: CoachSpot.myEventsCreate,
                    child: TestId('btn_new_event', child: FilledButton(
                      onPressed: () => _create(context, ref),
                      child: const Text('내 행사 만들기'),
                    )),
                  ),
                )
              else ...[
                const SectionTitle('내 행사'),
                for (final (i, s) in mine.indexed)
                  _firstTarget(
                    i,
                    TestId('event_item_${s.event.title}', child: EventTile(
                      event: s.event,
                      subtitle:
                          '${formatDate(s.event.date)} · 받은 사람 ${s.count}명 · ${formatWon(s.total)}',
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  EventDetailScreen(eventId: s.event.id!))),
                    )),
                  ),
              ],
              if (receptions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.section - 6),
                const AppDivider(),
                const SectionTitle('대신 받은 장부'),
                for (final s in receptions) _receptionRow(context, s),
              ],
              fabBottomSpace,
            ],
          );
        },
      ),
    );
  }

  /// 도움말이 첫 번째 행사를 가리킬 수 있게 한다.
  Widget _firstTarget(int index, Widget child) => index == 0
      ? CoachTarget(spot: CoachSpot.myEventsFirst, child: child)
      : child;

  Widget _receptionRow(BuildContext context, ReceptionSummary s) {
    final r = s.reception;
    final status = !r.isFinished
        ? '받는 중'
        : (r.imported ? '내 행사로 옮김' : '받기 끝남');
    return InkWell(
      onTap: () => Navigator.push(
          context,
          r.isFinished
              ? MaterialPageRoute<void>(
                  builder: (_) => ReceptionSummaryScreen(receptionId: r.id))
              : receptionReceiveRoute(r.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page, vertical: AppSpacing.item),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title,
                      style: AppText.listName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('$status · ${s.count}명 · ${formatWon(s.total)}',
                      style: AppText.sub.copyWith(
                          color: r.isFinished
                              ? AppColors.textSub
                              : AppColors.primary),
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
