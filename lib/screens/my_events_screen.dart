import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/common.dart';
import '../widgets/coach_mark.dart';
import '../widgets/screen_coach.dart';
import '../widgets/settings_button.dart';
import '../widgets/share_download.dart';
import 'event_detail_screen.dart';
import 'reception_summary_screen.dart';
import 'event_routes.dart';
import 'pick_event_screen.dart';

/// 행사 탭: '내 행사'와 '다른 사람 행사' 두 묶음. 남의 행사(일정)는 홈의 일정으로 간다.
/// 묶음 제목의 [+ 추가]로 그 종류의 행사를 만든다(내 행사는 누르는 순간 한도 검사).
class MyEventsScreen extends ConsumerWidget {
  const MyEventsScreen({super.key});

  /// 행사가 없을 때: 홈 '다가오는 일정이 없어요'와 같은 빈 화면 위젯([EmptyView])
  Widget _empty(BuildContext context) => ListView(
        padding: const EdgeInsets.only(top: AppSpacing.section),
        children: [
          TestId('events_empty', child: EmptyView(
            icon: Icons.event_available,
            message: '아직 행사가 없어요.',
            detail: '연필 버튼 > 받은 돈 적기에서 만들어요',
          )),
          fabBottomSpace,
        ],
      );

  /// 묶음 제목 줄: 왼쪽 '내 행사 1개 · 0원', 오른쪽 파란 글자 [+ 추가](누르는 영역 48dp)
  Widget _groupTitle(BuildContext context, WidgetRef ref,
          {required bool mine, required int count, required int total}) {
    final add = TestId(
      mine ? 'btn_add_my_event' : 'btn_add_other_event',
      child: TextButton(
        style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12)),
        onPressed: () => openCreateEventOf(context, ref, mine: mine),
        child: const Text('+ 추가', style: AppText.link),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.section - 12, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(mine ? '내 행사' : '다른 사람 행사', style: AppText.sectionTitle),
          const SizedBox(width: 10),
          Expanded(
            child: Text('$count개 · ${formatWon(total)}',
                style: AppText.sub, overflow: TextOverflow.ellipsis),
          ),
          // 도움말은 첫 묶음(내 행사)의 [+ 추가]를 가리킨다
          if (mine) CoachTarget(spot: CoachSpot.myEventsCreate, child: add) else add,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventSummariesProvider);
    final receptions =
        ref.watch(receptionSummariesProvider).value ?? const <ReceptionSummary>[];
    final mineCount = events.value?.where((s) => s.event.isMine).length ?? 0;
    // 행사 장부 전체 = 내 행사 + 아직 내 행사로 옮기지 않은 다른 사람 행사
    final ledgerCount =
        mineCount + receptions.where((s) => !s.reception.imported).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('행사'),
        actions: [
          // [공유] [다운로드]: 행사 장부 전체. 행사가 없으면 회색
          ShareDownloadButtons(
            spot: CoachSpot.myEventsShare,
            enabled: ledgerCount > 0,
            target: () => AllEventsExport(ref, count: ledgerCount),
          ),
          const HelpButton(screen: CoachScreen.myEvents),
          const SettingsButton(),
          SettingsButton.trailingGap,
        ],
      ),
      body: AsyncBody(
        value: events,
        builder: (all) {
          final mine = all.where((s) => s.event.isMine).toList();
          if (mine.isEmpty && receptions.isEmpty) return _empty(context);
          return ListView(
            children: [
              // 한 묶음이 비어 있어도 제목 줄('다른 사람 행사 0개 · 0원 + 추가')은 보인다
              _groupTitle(context, ref,
                  mine: true,
                  count: mine.length,
                  total: mine.fold(0, (s, e) => s + e.total)),
              ...[
                for (final (i, s) in mine.indexed)
                  _firstTarget(
                    i,
                    TestId('event_item_${s.event.title}', child: LedgerEventTile(
                      title: s.event.title,
                      isMine: true,
                      showKind: false,
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
              const SizedBox(height: AppSpacing.section - 14),
              const AppDivider(),
              _groupTitle(context, ref,
                  mine: false,
                  count: receptions.length,
                  total: receptions.fold(0, (s, r) => s + r.total)),
              ...[
                for (final (i, s) in receptions.indexed)
                  mine.isEmpty
                      ? _firstTarget(i, _receptionRow(context, s))
                      : _receptionRow(context, s),
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
    return TestId(
      'reception_item_${r.title}',
      child: LedgerEventTile(
        title: r.title,
        isMine: false,
        showKind: false,
        subtitle: '$status · ${s.count}명 · ${formatWon(s.total)}',
        subtitleHighlight: !r.isFinished,
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
                builder: (_) => ReceptionSummaryScreen(receptionId: r.id))),
      ),
    );
  }
}
