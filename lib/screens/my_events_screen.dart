import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'event_detail_screen.dart';
import 'event_form_screen.dart';
import 'reception_screen.dart';
import 'reception_summary_screen.dart';

/// 내 행사 탭: 내 행사와 접수 장부 목록. 남의 행사는 홈의 일정으로 간다.
class MyEventsScreen extends ConsumerWidget {
  const MyEventsScreen({super.key});

  void _create(BuildContext context) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => const EventFormScreen(initialIsMine: true)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventSummariesProvider);
    final receptions =
        ref.watch(receptionSummariesProvider).value ?? const <ReceptionSummary>[];
    final hasMine =
        events.value?.any((s) => s.event.isMine) ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 행사'),
        actions: [
          // 비어 있을 때는 화면 가운데 버튼 하나만 보여준다
          if (hasMine) ...[
            TextButton(
              onPressed: () => _create(context),
              child: const Text('내 행사 만들기'),
            ),
            const SizedBox(width: 8),
          ],
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
                  action: FilledButton(
                    onPressed: () => _create(context),
                    child: const Text('내 행사 만들기'),
                  ),
                )
              else
                for (final s in mine)
                  EventTile(
                    event: s.event,
                    subtitle:
                        '${formatDate(s.event.date)} · 받은 사람 ${s.count}명 · ${formatWon(s.total)}',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                EventDetailScreen(eventId: s.event.id!))),
                  ),
              if (receptions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.section - 6),
                const AppDivider(),
                const SectionTitle('접수 장부'),
                for (final s in receptions) _receptionRow(context, s),
              ],
              fabBottomSpace,
            ],
          );
        },
      ),
    );
  }

  Widget _receptionRow(BuildContext context, ReceptionSummary s) {
    final r = s.reception;
    final status = !r.isFinished
        ? '접수 중'
        : (r.imported ? '내 장부로 옮김' : '접수 완료');
    return InkWell(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => r.isFinished
                  ? ReceptionSummaryScreen(receptionId: r.id)
                  : ReceptionScreen(receptionId: r.id))),
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
