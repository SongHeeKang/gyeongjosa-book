import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../services/format.dart';
import '../services/notification_service.dart';
import '../widgets/common.dart';
import '../widgets/record_form_sheet.dart';
import 'event_form_screen.dart';
import 'quick_entry_screen.dart';

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
        return Scaffold(
          appBar: AppBar(
            title: Text(e.title),
            actions: [
              PopupMenuButton<String>(
                iconSize: 28,
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
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  [
                    '${e.isMine ? '내 행사' : '남의 행사'} · ${e.type}',
                    formatDate(e.date),
                    if ((e.place ?? '').isNotEmpty) e.place!,
                    if ((e.memo ?? '').isNotEmpty) e.memo!,
                    if (e.notify) '🔔 전날 오전 9시 알림',
                  ].join('\n'),
                  style: const TextStyle(fontSize: 17, color: Colors.black54, height: 1.5),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  Expanded(
                    child: Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.isMine ? '총 인원' : '보낸 건수',
                                style: const TextStyle(fontSize: 16)),
                            const SizedBox(height: 6),
                            Text('${main.length}명',
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  TotalTile(
                    label: e.isMine ? '받은 총액' : '보낸 총액',
                    amount: d.total,
                    color: e.isMine ? receivedColor : sentColor,
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: FilledButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => QuickEntryScreen(event: e))),
                  icon: const Icon(Icons.bolt),
                  label: Text(e.isMine ? '빠른 연속 입력 (받은 명단)' : '빠른 연속 입력 (보낸 돈)'),
                ),
              ),
              SectionTitle(e.isMine ? '받은 명단' : '보낸 내역'),
              if (d.records.isEmpty)
                EmptyView(
                    icon: Icons.list_alt,
                    message: e.isMine
                        ? '[빠른 연속 입력]으로 축의금 봉투를\n한 장씩 빠르게 입력해 보세요.'
                        : '아직 기록이 없어요.')
              else
                for (final r in d.records)
                  RecordTile(
                    record: r,
                    showPerson: true,
                    onTap: () => showRecordForm(context,
                        personId: r.personId, existing: r, event: e),
                  ),
            ],
          ),
        );
      },
    );
  }
}
