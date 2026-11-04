import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/event.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'event_detail_screen.dart';
import 'event_form_screen.dart';
import 'reception_form_screen.dart';
import 'reception_import_screen.dart';
import 'reception_screen.dart';
import 'reception_summary_screen.dart';

/// 장부 탭: 접수 시작 · 가져오기 / 내 행사 / 접수 장부 / 다가오는 남의 행사 / 지난 남의 행사
class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventSummariesProvider);
    final receptions =
        ref.watch(receptionSummariesProvider).value ?? const <ReceptionSummary>[];
    return Scaffold(
      appBar: AppBar(title: const Text('장부')),
      floatingActionButtonLocation: const PillFabLocation(),
      floatingActionButton: PillActionButton(
        label: '행사 추가',
        onPressed: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => const EventFormScreen())),
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
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => const ReceptionFormScreen())),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('접수 시작'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => pickAndOpenImport(context),
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('받은 장부 가져오기'),
                    ),
                  ],
                ),
              ),
              if (receptions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.section - 6),
                const AppDivider(),
                const SectionTitle('접수 장부'),
                for (final s in receptions) _receptionRow(context, s),
              ],
              const SizedBox(height: AppSpacing.section - 6),
              const AppDivider(),
              const SectionTitle('내 행사'),
              if (mine.isEmpty)
                const EmptyView(
                    icon: Icons.celebration_outlined,
                    message: '내 결혼식, 돌잔치처럼 내가 받은 행사를 등록하면\n받은 명단을 빠르게 정리할 수 있어요.')
              else
                for (final s in mine) _row(context, s),
              const SizedBox(height: AppSpacing.section - 6),
              const AppDivider(),
              const SectionTitle('다가오는 남의 행사'),
              if (upcoming.isEmpty)
                const EmptyView(
                    icon: Icons.event_available,
                    message: '다가오는 행사가 없어요.\n청첩장을 받으면 등록해 두세요. 전날 알려드려요.')
              else
                for (var i = 0; i < upcoming.length; i++)
                  _row(context, upcoming[i], highlight: i == 0),
              if (past.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.section - 6),
                const AppDivider(),
                ExpansionTile(
                  title: Text('지난 남의 행사 ${past.length}개',
                      style: AppText.sectionTitle),
                  children: [for (final s in past) _row(context, s)],
                ),
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

  Widget _row(BuildContext context, EventSummary s, {bool highlight = false}) {
    final e = s.event;
    final info = e.isMine
        ? '받은 사람 ${s.count}명 · ${formatWon(s.total)}'
        : (s.count > 0 ? '보낸 돈 ${formatWon(s.total)}' : (e.place ?? ''));
    return EventTile(
      event: e,
      highlight: highlight,
      subtitle: [formatDate(e.date), if (info.isNotEmpty) info].join(' · '),
      onTap: () => Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => EventDetailScreen(eventId: e.id!))),
    );
  }
}
