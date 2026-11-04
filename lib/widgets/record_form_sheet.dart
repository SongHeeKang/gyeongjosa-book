import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
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
      needsReview: widget.existing?.needsReview ?? false,
    );
    if (widget.existing == null) {
      await repo.insertRecord(record);
    } else {
      await repo.updateRecord(record);
    }
    ref.refreshData();
    if (mounted) Navigator.pop(context, true);
  }

  /// 확인 필요: 기존 사람이 맞음
  Future<void> _confirmSamePerson() async {
    await ref
        .read(repositoryProvider)
        .markRecordReviewed(widget.existing!.id!);
    ref.refreshData();
    if (mounted) Navigator.pop(context, true);
  }

  /// 확인 필요: 다른 사람이므로 같은 이름의 새 사람으로 분리
  Future<void> _splitToNewPerson() async {
    await ref.read(repositoryProvider).moveRecordToNewPerson(
        widget.existing!.id!, widget.existing!.personName ?? '');
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
      padding: EdgeInsets.fromLTRB(
          AppSpacing.page, 0, AppSpacing.page, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? '내역 추가' : '내역 수정',
                style: AppText.appTitle),
            const SizedBox(height: 16),
            if (widget.existing?.needsReview == true) ...[
              const Text('확인 필요', style: AppText.warning),
              const SizedBox(height: 4),
              Text(
                  '${widget.existing!.personName} 님과 같은 이름이 있어요. 같은 사람이 맞나요?',
                  style: AppText.body),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _confirmSamePerson,
                      child: const Text('같은 사람'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _splitToNewPerson,
                      child: const Text('다른 사람'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const AppDivider(),
              const SizedBox(height: 20),
            ],
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: Direction.sent, label: Text('보냄 (내가 냄)')),
                ButtonSegment(
                    value: Direction.received, label: Text('받음 (내가 받음)')),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
            const SizedBox(height: 20),
            const FieldLabel('금액'),
            AmountInput(controller: _amount, onChanged: () => setState(() {})),
            const SizedBox(height: 20),
            const FieldLabel('행사'),
            if (_hasFixedEvent)
              Text(
                widget.event?.title ??
                    widget.existing?.eventLabel ??
                    '',
                style: AppText.listName,
              )
            else
              ChoiceChips(
                options: EventTypes.all,
                selected: _eventType,
                onSelected: (v) => setState(() => _eventType = v),
              ),
            const SizedBox(height: 20),
            const FieldLabel('날짜'),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(formatDate(_date)),
            ),
            const SizedBox(height: 20),
            const FieldLabel('방법'),
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
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('이 내역 삭제'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
