import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../services/format.dart';
import 'amount_input.dart';
import 'common.dart';

/// 아래에서 올라오는 내역 입력/수정 창.
/// 저장하거나 삭제하면 true 를 돌려준다.
Future<bool> showRecordForm(
  BuildContext context, {
  required int personId,
  GiftRecord? existing,
  Event? event,
  String? initialDirection,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => RecordFormSheet(
      personId: personId,
      existing: existing,
      event: event,
      initialDirection: initialDirection,
    ),
  );
  return result == true;
}

class RecordFormSheet extends ConsumerStatefulWidget {
  const RecordFormSheet({
    super.key,
    required this.personId,
    this.existing,
    this.event,
    this.initialDirection,
  });
  final int personId;
  final GiftRecord? existing;
  final Event? event;
  final String? initialDirection;

  @override
  ConsumerState<RecordFormSheet> createState() => _RecordFormSheetState();
}

class _RecordFormSheetState extends ConsumerState<RecordFormSheet> {
  late String _direction;
  late String _eventType;
  late String _method;
  late DateTime _date;
  final _amount = TextEditingController();
  final _memo = TextEditingController();
  bool _saving = false;

  bool get _hasFixedEvent =>
      widget.event != null || widget.existing?.eventId != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _direction = e?.direction ??
        widget.initialDirection ??
        (widget.event?.isMine == true ? Direction.received : Direction.sent);
    _eventType = e?.eventType ?? widget.event?.type ?? EventTypes.all.first;
    _method = e?.method ?? Methods.all.first;
    _date = e?.date ?? widget.event?.date ?? DateTime.now();
    if (e != null) _amount.text = formatNumber(e.amount);
    _memo.text = e?.memo ?? '';
  }

  @override
  void dispose() {
    _amount.dispose();
    _memo.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1980),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    if (amount <= 0) {
      showSnack(context, '금액을 입력해 주세요.');
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    final eventId = widget.existing?.eventId ?? widget.event?.id;
    final record = GiftRecord(
      id: widget.existing?.id,
      personId: widget.existing?.personId ?? widget.personId,
      eventId: eventId,
      direction: _direction,
      amount: amount,
      method: _method,
      date: _date,
      memo: _memo.text.trim().isEmpty ? null : _memo.text.trim(),
      eventType: eventId == null ? _eventType : null,
    );
    if (widget.existing == null) {
      await repo.insertRecord(record);
    } else {
      await repo.updateRecord(record);
    }
    ref.refreshData();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: '내역 삭제', message: '이 내역을 삭제할까요?', okText: '삭제', destructive: true);
    if (!ok) return;
    await ref.read(repositoryProvider).deleteRecord(widget.existing!.id!);
    ref.refreshData();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? '내역 추가' : '내역 수정',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                minimumSize: const Size(0, 52),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                selectedBackgroundColor:
                    directionColor(_direction == Direction.sent)
                        .withValues(alpha: 0.15),
              ),
              segments: const [
                ButtonSegment(value: Direction.sent, label: Text('보냄 (내가 냄)')),
                ButtonSegment(
                    value: Direction.received, label: Text('받음 (내가 받음)')),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
            const SizedBox(height: 20),
            const _Label('금액'),
            AmountInput(controller: _amount, onChanged: () => setState(() {})),
            const SizedBox(height: 20),
            const _Label('행사'),
            if (_hasFixedEvent)
              Text(
                widget.event?.title ??
                    widget.existing?.eventLabel ??
                    '',
                style: const TextStyle(fontSize: 18),
              )
            else
              ChoiceChips(
                options: EventTypes.all,
                selected: _eventType,
                onSelected: (v) => setState(() => _eventType = v),
              ),
            const SizedBox(height: 20),
            const _Label('날짜'),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(formatDate(_date)),
            ),
            const SizedBox(height: 20),
            const _Label('방법'),
            ChoiceChips(
              options: Methods.all,
              selected: _method,
              onSelected: (v) => setState(() => _method = v),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _memo,
              decoration: const InputDecoration(labelText: '메모 (선택)'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('저장'),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _delete,
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: const Text('이 내역 삭제'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 16, color: Colors.black54)),
      );
}
