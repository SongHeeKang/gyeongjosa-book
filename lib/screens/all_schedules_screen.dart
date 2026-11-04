import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/event.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'event_detail_screen.dart';

/// 일정 전체 보기: 다가오는 일정과 지난 일정 (남의 행사만)
class AllSchedulesScreen extends ConsumerWidget {
  const AllSchedulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('일정 전체')),
      body: AsyncBody(
        value: ref.watch(eventSummariesProvider),
        builder: (all) {
          final today = dateOnly(DateTime.now());
          final others = all.where((s) => !s.event.isMine);
          final upcoming = others
              .where((s) => !s.event.date.isBefore(today))
              .toList()
            ..sort((a, b) => a.event.date.compareTo(b.event.date));
          final past =
              others.where((s) => s.event.date.isBefore(today)).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SectionTitle('다가오는 일정'),
              if (upcoming.isEmpty)
                const EmptyView(
                    icon: Icons.event_available, message: '다가오는 일정이 없어요.')
              else
                for (var i = 0; i < upcoming.length; i++)
                  _row(context, upcoming[i], highlight: i == 0),
              if (past.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.section - 6),
                const AppDivider(),
                const SectionTitle('지난 일정'),
                for (final s in past) _row(context, s),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, EventSummary s, {bool highlight = false}) {
    final e = s.event;
    final info = s.count > 0 ? '보낸 돈 ${formatWon(s.total)}' : (e.place ?? '');
    return EventTile(
      event: e,
      highlight: highlight,
      subtitle: [formatDate(e.date), if (info.isNotEmpty) info].join(' · '),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => EventDetailScreen(eventId: e.id!))),
    );
  }
}
