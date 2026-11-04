import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/event.dart';
import '../screens/event_form_screen.dart';
import '../screens/quick_entry_screen.dart';
import '../screens/reception_form_screen.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import 'person_picker_sheet.dart';

enum _RecordAction { sent, schedule, received, reception }

/// [+ 기록하기]: 큰 선택지 4개를 고르면 해당 화면으로 간다.
Future<void> showRecordMenu(BuildContext context, WidgetRef ref) async {
  final action = await showModalBottomSheet<_RecordAction>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _RecordMenuSheet(),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _RecordAction.sent:
      await startSentRecord(context, ref);
    case _RecordAction.schedule:
      await Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => const EventFormScreen()));
    case _RecordAction.received:
      await _startReceivedEntry(context, ref);
    case _RecordAction.reception:
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => const ReceptionFormScreen()));
  }
}

/// [받은 돈 정리]: 내 행사를 고르고(없으면 바로 만들고) 연속 입력으로 간다.
Future<void> _startReceivedEntry(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  final mine = await repo.myEvents();
  if (!context.mounted) return;

  Event? event;
  var createNew = mine.isEmpty;
  if (mine.length == 1) event = mine.first;
  if (mine.length > 1) {
    final picked = await showModalBottomSheet<_EventPick>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _MyEventPickerSheet(events: mine),
    );
    if (picked == null || !context.mounted) return;
    event = picked.event;
    createNew = picked.event == null;
  }
  if (createNew) {
    final id = await Navigator.push<int>(
        context,
        MaterialPageRoute<int>(
            builder: (_) => const EventFormScreen(initialIsMine: true)));
    if (id == null) return;
    event = await repo.getEvent(id);
    if (!context.mounted) return;
  }
  final target = event;
  if (target == null) return;
  await Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => QuickEntryScreen(event: target)));
}

class _EventPick {
  final Event? event; // null이면 새로 만들기
  const _EventPick(this.event);
}

class _RecordMenuSheet extends StatelessWidget {
  const _RecordMenuSheet();

  @override
  Widget build(BuildContext context) {
    Widget item(_RecordAction action, IconData icon, String title, String sub) =>
        ListTile(
          minTileHeight: 72,
          leading: Icon(icon, size: 28, color: AppColors.primary),
          title: Text(title, style: AppText.sectionTitle),
          subtitle: Text(sub),
          onTap: () => Navigator.pop(context, action),
        );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          item(_RecordAction.sent, Icons.card_giftcard, '보냈어요',
              '축의금 · 부의금을 냈어요'),
          item(_RecordAction.schedule, Icons.event_outlined, '일정 추가',
              '청첩장 · 부고를 받았어요'),
          item(_RecordAction.received, Icons.playlist_add, '받은 돈 정리',
              '내 행사 명단을 적어요'),
          item(_RecordAction.reception, Icons.edit_note, '행사장 접수',
              '접수대에서 바로 받아요'),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _MyEventPickerSheet extends StatelessWidget {
  const _MyEventPickerSheet({required this.events});
  final List<Event> events;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding:
                EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 12),
            child: Text('어느 행사의 명단인가요?', style: AppText.appTitle),
          ),
          for (final e in events)
            ListTile(
              title: Text(e.title),
              subtitle: Text(formatDate(e.date)),
              onTap: () => Navigator.pop(context, _EventPick(e)),
            ),
          ListTile(
            leading: const Icon(Icons.add, color: AppColors.primary),
            title: Text('새 내 행사 만들기',
                style: AppText.listName.copyWith(color: AppColors.primary)),
            onTap: () => Navigator.pop(context, const _EventPick(null)),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
