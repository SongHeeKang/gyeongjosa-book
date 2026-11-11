import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import 'amount_input.dart';
import 'common.dart';
import 'person_picker_sheet.dart';

/// 홈의 '얼마 내셨어요?': 날짜가 지난 일정에 금액을 바로 적는다.
class PendingAmountSection extends StatelessWidget {
  const PendingAmountSection({super.key, required this.events});
  final List<Event> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('얼마 내셨어요?'),
        for (final e in events) _PendingRow(event: e),
        const SizedBox(height: AppSpacing.section - 6),
        const AppDivider(),
      ],
    );
  }
}

class _PendingRow extends ConsumerStatefulWidget {
  const _PendingRow({required this.event});
  final Event event;

  @override
  ConsumerState<_PendingRow> createState() => _PendingRowState();
}

class _PendingRowState extends ConsumerState<_PendingRow> {
  static const _amounts = [50000, 100000, 200000];

  bool _busy = false;

  Event get event => widget.event;

  /// 일정에 연결된 '보냄' 기록을 만든다. 그러면 이 줄은 목록에서 사라진다.
  Future<void> _record(int amount) async {
    if (_busy) return;
    _busy = true;
    try {
      // 이전 버전에서 만든 일정은 사람이 연결되어 있지 않아 물어본다.
      final personId = event.personId ??
          await pickPerson(context, ref, title: '누구에게 보냈나요?');
      if (personId == null) return;
      await ref.read(repositoryProvider).insertRecord(GiftRecord(
            personId: personId,
            eventId: event.id,
            direction: Direction.sent,
            amount: amount,
            method: Methods.all.first,
            date: event.date,
          ));
      ref.refreshData();
      if (mounted) {
        showSnack(context, '${event.title}에 ${formatWon(amount)}을 기록했어요.');
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _enterAmount() async {
    final amount = await showAmountDialog(context);
    if (amount != null && mounted) await _record(amount);
  }

  Future<void> _hide() async {
    await ref.read(repositoryProvider).hidePendingEvent(event.id!);
    ref.refreshData();
  }

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.styleFrom(padding: EdgeInsets.zero);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.page, vertical: AppSpacing.item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title,
                        style: AppText.listName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(formatDate(event.date), style: AppText.sub),
                  ],
                ),
              ),
              TestId(
                'ask_skip',
                child: TextButton(
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.textSub),
                  onPressed: _hide,
                  child: const Text('안 갔어요'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final a in _amounts) ...[
                Expanded(
                  child: TestId(
                    'ask_amount_$a',
                    child: OutlinedButton(
                      style: button,
                      onPressed: () => _record(a),
                      child: Text(formatManWon(a)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TestId(
                  'ask_custom',
                  child: OutlinedButton(
                    style: button,
                    onPressed: _enterAmount,
                    child: const Text('직접'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
