import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/common.dart';
import '../widgets/coach_mark.dart';
import '../widgets/screen_coach.dart';
import '../widgets/settings_button.dart';
import 'event_detail_screen.dart';
import 'reception_summary_screen.dart';
import 'event_routes.dart';
import 'ledger_import_screen.dart';
import 'pick_event_screen.dart';

/// 행사 탭: '내 행사'와 '다른 사람 행사' 두 묶음. 남의 행사(일정)는 홈의 일정으로 간다.
/// [행사 만들기]에서 누구 행사인지 고르고, 내 행사 한도는 그때 검사한다.
class MyEventsScreen extends ConsumerWidget {
  const MyEventsScreen({super.key});

  Widget _createButton(BuildContext context, {bool filled = false}) =>
      CoachTarget(
        spot: CoachSpot.myEventsCreate,
        child: TestId(
            'btn_new_event',
            child: filled
                ? FilledButton(
                    onPressed: () => openCreateEvent(context),
                    child: const Text('행사 만들기'))
                : TextButton(
                    onPressed: () => openCreateEvent(context),
                    child: const Text('행사 만들기'))),
      );

  Widget _importButton(BuildContext context) => TestId(
        'btn_tab_import',
        child: OutlinedButton.icon(
          onPressed: () => openLedgerImport(context),
          icon: const Icon(Icons.content_paste_go_outlined),
          label: const Text('받은 장부 가져오기'),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventSummariesProvider);
    final receptions =
        ref.watch(receptionSummariesProvider).value ?? const <ReceptionSummary>[];
    final hasAny =
        (events.value?.any((s) => s.event.isMine) ?? false) || receptions.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('행사'),
        actions: [
          // 비어 있을 때는 화면 가운데 버튼만 보여준다
          if (hasAny) _createButton(context),
          const HelpButton(screen: CoachScreen.myEvents),
          const SettingsButton(),
          SettingsButton.trailingGap,
        ],
      ),
      body: AsyncBody(
        value: events,
        builder: (all) {
          final mine = all.where((s) => s.event.isMine).toList();
          if (mine.isEmpty && receptions.isEmpty) {
            return ListView(children: [
              EmptyView(
                icon: Icons.celebration_outlined,
                message: '결혼식 · 돌잔치에서 받은 돈을\n행사별로 적어 보세요',
                action: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _createButton(context, filled: true),
                    const SizedBox(height: 8),
                    _importButton(context),
                  ],
                ),
              ),
            ]);
          }
          return ListView(
            children: [
              if (mine.isNotEmpty) ...[
                const SectionTitle('내 행사'),
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
                const SectionTitle('다른 사람 행사'),
                for (final (i, s) in receptions.indexed)
                  mine.isEmpty
                      ? _firstTarget(i, _receptionRow(context, s))
                      : _receptionRow(context, s),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, AppSpacing.section, AppSpacing.page, 0),
                child: _importButton(context),
              ),
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
