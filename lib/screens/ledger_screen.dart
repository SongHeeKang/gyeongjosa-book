import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/event.dart';
import '../services/format.dart';
import '../widgets/common.dart';
import 'event_detail_screen.dart';
import 'event_form_screen.dart';

/// 장부 탭: 내 행사 / 다가오는 남의 행사 / 지난 남의 행사
class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventSummariesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('장부')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => const EventFormScreen())),
        icon: const Icon(Icons.add),
        label: const Text('행사 추가', style: TextStyle(fontSize: 18)),
      ),
      body: AsyncBody(
        value: events,
        builder: (all) {
          final today = dateOnly(DateTime.now());
          final mine = all.where((s) => s.event.isMine).toList();
          final others = all.where((s) => !s.event.isMine);
          final upcoming = others
              .where((s) => !s.event.date.isBefore(today))
              .toList()
            ..sort((a, b) => a.event.date.compareTo(b.event.date));
          final past =
              others.where((s) => s.event.date.isBefore(today)).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              const SectionTitle('내 행사'),
              if (mine.isEmpty)
                const EmptyView(
                    icon: Icons.celebration_outlined,
                    message: '내 결혼식, 돌잔치처럼 내가 받은 행사를 등록하면\n받은 명단을 빠르게 정리할 수 있어요.')
              else
                for (final s in mine) _EventRow(summary: s),
              const SectionTitle('다가오는 남의 행사'),
              if (upcoming.isEmpty)
                const EmptyView(
                    icon: Icons.event_available,
                    message: '다가오는 행사가 없어요.\n청첩장을 받으면 등록해 두세요. 전날 알려드려요.')
              else
                for (final s in upcoming) _EventRow(summary: s),
              if (past.isNotEmpty)
                ExpansionTile(
                  title: Text('지난 남의 행사 ${past.length}개',
                      style: Theme.of(context).textTheme.titleMedium),
                  children: [for (final s in past) _EventRow(summary: s)],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.summary});
  final EventSummary summary;

  @override
  Widget build(BuildContext context) {
    final e = summary.event;
    final isUpcoming = !e.date.isBefore(dateOnly(DateTime.now()));
    final info = e.isMine
        ? '받은 사람 ${summary.count}명 · ${formatWon(summary.total)}'
        : (summary.count > 0 ? '보낸 돈 ${formatWon(summary.total)}' : (e.place ?? ''));
    return ListTile(
      onTap: () => Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => EventDetailScreen(eventId: e.id!))),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: e.isMine
            ? receivedColor.withValues(alpha: 0.12)
            : Theme.of(context).colorScheme.secondaryContainer,
        child: Text(e.type.characters.first, style: const TextStyle(fontSize: 18)),
      ),
      title: Text(e.title),
      subtitle: Text([formatDate(e.date), if (info.isNotEmpty) info].join('\n')),
      isThreeLine: info.isNotEmpty,
      trailing: isUpcoming
          ? Text(dDay(e.date),
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary))
          : const Icon(Icons.chevron_right),
    );
  }
}
