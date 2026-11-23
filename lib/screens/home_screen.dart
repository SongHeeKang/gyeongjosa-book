import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../services/app_config.dart';
import '../services/format.dart';
import '../services/notification_permission.dart';
import '../theme/app_theme.dart';
import '../widgets/backup_guide.dart';
import '../widgets/grouped_bar_chart.dart';
import '../widgets/test_id.dart';
import '../widgets/coach_mark.dart';
import '../widgets/common.dart';
import '../widgets/pending_amount_section.dart';
import '../widgets/screen_coach.dart';
import '../widgets/settings_button.dart';
import 'all_records_screen.dart';
import 'all_schedules_screen.dart';
import 'event_detail_screen.dart';
import 'person_detail_screen.dart';
import '../widgets/share_download.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.showBackup = kShowHomeBackup});

  /// 요약 카드 제목 줄 오른쪽의 백업 아이콘 ([kShowHomeBackup], 테스트에서 바꿔 본다)
  final bool showBackup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final year = DateTime.now().year;
    return Scaffold(
      appBar: AppBar(
        title: const Text('경조사 장부'),
        actions: [
          // [공유] [다운로드]: 개인으로 보내고 받은 모든 내역 (무료). 기록이 없으면 회색
          ShareDownloadButtons(
            spot: CoachSpot.homeExcel,
            enabled: (home.value?.recordCount ?? 0) > 0,
            target: () =>
                HistoryExport(ref, count: home.value?.recordCount ?? 0),
          ),
          const CoachTarget(
            spot: CoachSpot.homeHelp,
            child: HelpButton(screen: CoachScreen.home),
          ),
          const SettingsButton(),
          SettingsButton.trailingGap,
        ],
      ),
      body: AsyncBody(
        value: home,
        builder: (data) => ListView(
          children: [
            // 요약 카드 제목 줄: 왼쪽 '2026년 나의 경조사', 오른쪽 백업 아이콘(v1에서는 숨김)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page, 4, AppSpacing.page - 8, 4),
              child: Row(
                children: [
                  Expanded(
                      child: Text('$year년 나의 경조사', style: AppText.label)),
                  if (showBackup)
                    BackupStatusButton(recordCount: data.recordCount)
                  else
                    // 아이콘이 없어도 제목 줄 높이는 같게
                    const SizedBox(height: 48),
                ],
              ),
            ),
            SummaryRow(
              sent: data.sent,
              received: data.received,
              sentCount: data.sentCount,
              receivedCount: data.receivedCount,
              sentId: 'home_sent_total',
              receivedId: 'home_received_total',
            ),
            const SizedBox(height: AppSpacing.section),
            const AppDivider(),
            if (data.pending.isNotEmpty)
              CoachTarget(
                spot: CoachSpot.homePending,
                child: TestId('ask_card',
                    child: PendingAmountSection(events: data.pending)),
              ),
            // 다가오는 일정: 일정이 없어도 섹션은 늘 보이고 빈 화면 문구만 (추가 X)
            ...[
              SectionTitle(
                '다가오는 일정',
                trailing: data.scheduleCount == 0
                    ? null
                    : TestId('btn_all_schedules', child: LinkText('전체 보기',
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => const AllSchedulesScreen())))),
              ),
              if (data.upcoming.isEmpty)
                const TestId('home_no_schedule', child: EmptyView(
                    icon: Icons.event_available, message: '다가오는 일정이 없어요.'))
              else
                for (var i = 0; i < data.upcoming.length; i++)
                  EventTile(
                    event: data.upcoming[i],
                    highlight: i == 0,
                    subtitle: [
                      formatDate(data.upcoming[i].date),
                      data.upcoming[i].personRelation ?? data.upcoming[i].type,
                    ].join(' · '),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => EventDetailScreen(
                                eventId: data.upcoming[i].id!))),
                  ),
              if (data.upcoming.isNotEmpty) const _NotificationOffLine(),
              const SizedBox(height: AppSpacing.section - 6),
              const AppDivider(),
            ],
            const _RecentMonthsSection(),
            SectionTitle(
              '최근 기록',
              trailing: data.recent.isEmpty
                  ? null
                  : TestId('btn_all_records', child: LinkText('전체 보기',
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => const AllRecordsScreen())))),
            ),
            if (data.recent.isEmpty)
              const TestId(
                'home_empty',
                child: EmptyView(
                  icon: Icons.receipt_long,
                  message: '아직 기록이 없어요.\n오른쪽 아래 연필 버튼을 눌러 첫 기록을 남겨보세요',
                ),
              )
            else
              for (final r in data.recent)
                RecordTile(
                  record: r,
                  showPerson: true,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) =>
                              PersonDetailScreen(personId: r.personId))),
                ),
            fabBottomSpace,
          ],
        ),
      ),
    );
  }
}

/// 홈 '최근 6개월': 이번 달을 포함한 6개월의 보냄 / 받음 막대(통계 탭 월별 그래프와 같은 위젯을 작게).
/// 그래프나 '통계 ›'를 누르면 통계 탭으로. 무료 · 프로 모두.
/// 기록이 없어도 틀(0 축 · 월 라벨 · 범례)은 그대로 두고 막대만 없이 "기록이 생기면 여기에 보여요".
class _RecentMonthsSection extends ConsumerWidget {
  const _RecentMonthsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 처음 읽는 동안에도 틀이 흔들리지 않게, 값이 없으면 이번 달까지 6개월을 0으로 둔다
    final now = DateTime.now();
    final rows = ref.watch(recentMonthsProvider).value ??
        [
          for (var i = 5; i >= 0; i--)
            (
              year: DateTime(now.year, now.month - i).year,
              month: DateTime(now.year, now.month - i).month,
              sent: 0,
              received: 0,
            ),
        ];
    final empty = rows.every((r) => r.sent == 0 && r.received == 0);
    void openStats() => ref.read(tabRequestProvider.notifier).go(AppTabs.stats);
    return TestId('home_recent_months', child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          '최근 6개월',
          trailing: TestId('btn_home_stats',
              child: LinkText('통계 ›', onTap: openStats)),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: openStats,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.page - 12, 8, AppSpacing.page, 0),
            child: SizedBox(
              height: 160,
              // 막대를 눌러도 말풍선 대신 통계 탭으로 가도록 그래프 터치는 끈다
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: GroupedBarChart(
                        labels: [for (final r in rows) '${r.month}월'],
                        sent: [for (final r in rows) r.sent],
                        received: [for (final r in rows) r.received],
                        compact: true,
                      ),
                    ),
                  ),
                  if (empty)
                    // 아래 월 라벨 자리(30)를 빼고 그래프 영역 가운데에
                    Positioned.fill(
                      bottom: 30,
                      left: 40,
                      child: Center(
                        child: TestId(
                          'home_months_empty',
                          // 눈금 선 위에 겹쳐도 읽히게 흰 바탕을 깐다
                          child: ColoredBox(
                            color: AppColors.background,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              child: Text('기록이 생기면 여기에 보여요',
                                  style: AppText.sub
                                      .copyWith(color: AppColors.textHint)),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.page, 6, AppSpacing.page, 0),
          child: Align(
              alignment: Alignment.centerRight, child: SentReceivedLegend()),
        ),
        const SizedBox(height: AppSpacing.section - 6),
        const AppDivider(),
      ],
    ));
  }
}

/// 다가오는 일정 아래: 알림이 꺼져 있으면 작은 회색 한 줄 "알림이 꺼져 있어요" + [켜기].
/// [켜기]는 허용 창을 다시 띄우고, 더 띄울 수 없으면 휴대폰 알림 설정을 연다.
/// 앱으로 돌아오면 MainShell이 상태를 다시 확인하고, 켜져 있으면 이 줄은 사라진다.
class _NotificationOffLine extends ConsumerWidget {
  const _NotificationOffLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(notificationPermissionProvider)) return const SizedBox.shrink();
    return TestId('home_notification_off', child: Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, 8, 0),
      child: Row(
        children: [
          const Icon(Icons.notifications_off_outlined,
              size: 18, color: AppColors.textSub),
          const SizedBox(width: 6),
          const Flexible(child: Text('알림이 꺼져 있어요', style: AppText.sub)),
          TestId('btn_notification_on', child: TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => requestNotificationsOrOpenSettings(ref),
            child: const Text('켜기', style: AppText.link),
          )),
        ],
      ),
    ));
  }
}
