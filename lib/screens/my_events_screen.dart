import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/common.dart';
import '../widgets/coach_mark.dart';
import '../widgets/dashed_box.dart';
import '../widgets/screen_coach.dart';
import '../widgets/settings_button.dart';
import '../widgets/share_download.dart';
import 'event_detail_screen.dart';
import 'reception_summary_screen.dart';
import 'event_routes.dart';
import 'ledger_import_screen.dart';
import 'pick_event_screen.dart';

/// 행사 탭: '내 행사'와 '다른 사람 행사' 두 묶음. 남의 행사(일정)는 홈의 일정으로 간다.
/// [행사 만들기]에서 누구 행사인지 고르고, 내 행사 한도는 그때 검사한다.
class MyEventsScreen extends ConsumerWidget {
  const MyEventsScreen({super.key});

  /// 맨 아래 작은 글자 링크
  Widget _importLink(BuildContext context) => Center(
        child: TestId(
          'btn_tab_import',
          child: LinkText('받은 장부 붙여넣어 가져오기',
              onTap: () => openLedgerImport(context)),
        ),
      );

  /// 행사가 없을 때: 둥근 배경 아이콘 · 안내 · 점선 카드 · 흐린 예시 줄 · 가져오기 링크
  Widget _empty(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.section * 2, AppSpacing.page, 0),
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                  color: AppColors.primarySoft, shape: BoxShape.circle),
              child: const Icon(Icons.celebration_outlined,
                  size: 42, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 20),
          const Text('첫 행사 장부를 만들어 보세요',
              textAlign: TextAlign.center, style: AppText.appTitle),
          const SizedBox(height: 8),
          Text('결혼식 · 돌잔치 · 장례식\n받은 마음을 행사별로 모아 둬요',
              textAlign: TextAlign.center,
              style: AppText.sub.copyWith(fontSize: 15, height: 1.5)),
          const SizedBox(height: AppSpacing.section),
          CoachTarget(
            spot: CoachSpot.myEventsCreate,
            child: TestId(
              'btn_new_event',
              child: DashedBox(
                onTap: () => openCreateEvent(context),
                child: const Padding(
                  padding: EdgeInsets.all(18),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.primary,
                        child: Icon(Icons.add, color: AppColors.background),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('행사를 추가해 주세요', style: AppText.sectionTitle),
                            SizedBox(height: 2),
                            Text('내 행사 · 다른 사람 행사', style: AppText.sub),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // 누를 수 없는 흐린 예시 줄
          ExcludeSemantics(
            child: Opacity(
              opacity: 0.45,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text('예) 우리 결혼식 · 2026.10.11 · 0명', style: AppText.body),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          _importLink(context),
          fabBottomSpace,
        ],
      );

  /// 묶음 제목 옆의 개수 · 합계 (예: '11개 · 1,850,000원')
  Widget _groupTitle(String title, int count, int total) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.section, AppSpacing.page, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(title, style: AppText.sectionTitle),
            const SizedBox(width: 10),
            Flexible(
              child: Text('$count개 · ${formatWon(total)}',
                  style: AppText.sub, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );

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
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, 12, AppSpacing.page, 0),
                child: CoachTarget(
                  spot: CoachSpot.myEventsCreate,
                  child: TestId(
                    'btn_new_event',
                    child: DashedBox(
                      radius: 12,
                      onTap: () => openCreateEvent(context),
                      child: const SizedBox(
                        height: 52,
                        child: Center(
                          child: Text('+ 새 행사 만들기',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (mine.isNotEmpty) ...[
                _groupTitle('내 행사', mine.length,
                    mine.fold(0, (s, e) => s + e.total)),
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
              if (receptions.isNotEmpty) ...[
                if (mine.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.section - 6),
                  const AppDivider(),
                ],
                _groupTitle('다른 사람 행사', receptions.length,
                    receptions.fold(0, (s, r) => s + r.total)),
                for (final (i, s) in receptions.indexed)
                  mine.isEmpty
                      ? _firstTarget(i, _receptionRow(context, s))
                      : _receptionRow(context, s),
              ],
              const SizedBox(height: AppSpacing.section - 8),
              _importLink(context),
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
