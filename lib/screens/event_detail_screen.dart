import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../services/format.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/coach_mark.dart';
import '../widgets/common.dart';
import '../widgets/record_form_sheet.dart';
import '../widgets/screen_coach.dart';
import 'event_form_screen.dart';
import 'quick_entry_screen.dart';
import 'reception_form_screen.dart';
import 'reception_import_screen.dart';

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
              if (e.isMine) const HelpButton(screen: CoachScreen.eventDetail),
              PopupMenuButton<String>(
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
              ),
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
                          if (e.notify) '전날 오전 9시 알림',
                        ].join('\n'),
                        style: AppText.sub.copyWith(height: 1.6),
                      ),
                    ),
                    if (upcoming)
                      Text(dDay(e.date),
                          style: AppText.dDay.copyWith(color: AppColors.primary)),
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
                        spot: CoachSpot.eventReception,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (_) =>
                                      ReceptionFormScreen(event: e))),
                          icon: const Icon(Icons.edit_note),
                          label: const Text('행사장 접수'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      CoachTarget(
                        spot: CoachSpot.eventDirect,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (_) => QuickEntryScreen(event: e))),
                          icon: const Icon(Icons.bolt, size: 20),
                          label: const Text('받은 명단 직접 입력'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      CoachTarget(
                        spot: CoachSpot.eventImport,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              pickAndOpenImport(context, eventId: e.id),
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('장부 가져오기'),
                        ),
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
                        ? '[받은 명단 직접 입력]으로 축의금 봉투를\n한 장씩 빠르게 입력해 보세요.'
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
