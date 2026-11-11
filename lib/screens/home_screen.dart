import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../services/format.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
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
import 'settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final year = DateTime.now().year;
    return Scaffold(
      appBar: AppBar(
        title: const Text('경조사 장부'),
        actions: [
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
            _BackupBanner(recordCount: data.recordCount),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page, 12, AppSpacing.page, 12),
              child: Text('$year년 나의 경조사', style: AppText.label),
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
            if (data.scheduleCount > 0) ...[
              SectionTitle(
                '다가오는 일정',
                trailing: TestId('btn_all_schedules', child: LinkText('전체 보기',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const AllSchedulesScreen())))),
              ),
              if (data.upcoming.isEmpty)
                const EmptyView(
                    icon: Icons.event_available, message: '다가오는 일정이 없어요.')
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
              const SizedBox(height: AppSpacing.section - 6),
              const AppDivider(),
            ],
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

/// 기록 20개 이상인데 백업을 안 했거나 30일이 지나면 보이는 배너
class _BackupBanner extends ConsumerWidget {
  const _BackupBanner({required this.recordCount});
  final int recordCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = shouldShowBackupBanner(
      recordCount: recordCount,
      lastBackup: ref.watch(lastBackupProvider),
      dismissedAt: ref.watch(bannerDismissProvider),
    );
    if (!show) return const SizedBox.shrink();
    return TestId('backup_banner', child: Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 8),
      child: Material(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(context,
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Row(
              children: [
                const Icon(Icons.cloud_upload_outlined,
                    size: 22, color: AppColors.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('백업해 두면 폰을 바꿔도 기록이 안전해요',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text)),
                ),
                IconButton(
                  tooltip: '닫기',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () =>
                      ref.read(bannerDismissProvider.notifier).dismiss(),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}
