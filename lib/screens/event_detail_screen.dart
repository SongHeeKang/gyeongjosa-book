import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../services/format.dart';
import '../services/notification_permission.dart';
import '../services/reminder_format.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/coach_mark.dart';
import '../widgets/common.dart';
import '../widgets/record_form_sheet.dart';
import '../widgets/screen_coach.dart';
import 'event_actions.dart';
import 'event_form_screen.dart';
import 'quick_entry_screen.dart';
import 'event_routes.dart';
import '../widgets/share_download.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final int eventId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(context,
        title: '행사 삭제',
        message: '행사만 삭제되고, 사람별 내역은 그대로 남아요.\n삭제할까요?',
        okText: '삭제',
        destructive: true);
    if (!ok) return;
    await NotificationService.instance.cancelForEvent(eventId);
    await ref.read(repositoryProvider).deleteEvent(eventId);
    ref.refreshData();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(eventDetailProvider(eventId));
    return AsyncBody(
      value: detail,
      builder: (d) {
        if (d == null) {
          return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('삭제된 행사예요.')));
        }
        final e = d.event;
        final main = d.mainRecords;
        final upcoming = !e.date.isBefore(dateOnly(DateTime.now()));
        return Scaffold(
          appBar: AppBar(
            title: Text(e.title),
            actions: [
              // [공유] [다운로드]: 이 행사 하나. 받은 사람이 없으면 회색
              if (e.isMine)
                ShareDownloadButtons(
                  spot: CoachSpot.eventSend,
                  enabled: main.isNotEmpty,
                  target: () => MyEventExport(ref, event: e, records: main),
                ),
              if (e.isMine) const HelpButton(screen: CoachScreen.eventDetail),
              if (!e.isMine)
              TestId('event_menu', child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.icon),
                onSelected: (v) {
                  if (v == 'edit') {
                    Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => EventFormScreen(existing: e)));
                  }
                  if (v == 'delete') _delete(context, ref);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('행사 수정')),
                  PopupMenuItem(value: 'delete', child: Text('삭제')),
                ],
              )),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, 0, AppSpacing.page, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        [
                          '${e.isMine ? '내 행사' : '남의 행사'} · ${e.type}',
                          formatDate(e.date),
                          if ((e.place ?? '').isNotEmpty) e.place!,
                          if ((e.memo ?? '').isNotEmpty) e.memo!,
                          if (e.hasReminder)
                            ref.watch(notificationPermissionProvider)
                                ? '알림: ${reminderLabel(e)}'
                                : '알림: ${reminderLabel(e)} (알림 권한이 꺼져 있어요)',
                        ].join('\n'),
                        style: AppText.sub.copyWith(height: 1.6),
                      ),
                    ),
                    if (upcoming)
                      Text(dDay(e.date),
                          style: AppText.dDay.copyWith(color: AppColors.primary)),
                    // 추가 AA: 행사 정보 오른쪽 [수정] → 행사 수정 화면(맨 아래 [행사 삭제])
                    if (e.isMine)
                      CoachTarget(
                        spot: CoachSpot.eventEdit,
                        child: TestId(
                        'btn_event_edit',
                        child: TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            foregroundColor: AppColors.primary,
                          ),
                          onPressed: () => openEditMyEvent(context, e, main),
                          child: const Text('수정', style: AppText.link),
                        ),
                      ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.isMine ? '총 인원' : '보낸 건수', style: AppText.label),
                        const SizedBox(height: 4),
                        Text('${main.length}명', style: AppText.summaryAmount),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SummaryColumn(
                    label: e.isMine ? '받은 총액' : '보낸 총액',
                    amount: d.total,
                    highlight: e.isMine,
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, 20, AppSpacing.page, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (e.isMine) ...[
                      AutoCoach(
                          prefs: ref.read(prefsProvider),
                          screen: CoachScreen.eventDetail),
                      CoachTarget(
                        spot: CoachSpot.eventReceive,
                        child: TestId('btn_event_receive', child: FilledButton.icon(
                          onPressed: () =>
                              Navigator.push(context, myEventReceiveRoute(e)),
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('장부 작성'),
                        )),
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => QuickEntryScreen(event: e))),
                        icon: const Icon(Icons.bolt, size: 20),
                        label: const Text('빠른 연속 입력 (보낸 돈)'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              const AppDivider(),
              SectionTitle(e.isMine ? '받은 명단' : '보낸 내역'),
              if (d.records.isEmpty)
                EmptyView(
                    icon: Icons.list_alt,
                    message: e.isMine
                        ? '[장부 작성]으로 축의금 봉투를\n한 장씩 빠르게 입력해 보세요.'
                        : '아직 기록이 없어요.')
              else
                for (final r in d.records)
                  RecordTile(
                    record: r,
                    showPerson: true,
                    onTap: () => showRecordForm(context,
                        personId: r.personId, existing: r, event: e),
                  ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
