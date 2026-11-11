import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import 'amount_input.dart';
import 'common.dart';

/// 접수 항목 한 줄: 이름 / 구분 · 저장 시각 · 식권 · 방법 · 메모 / 금액
class ReceptionEntryTile extends StatelessWidget {
  const ReceptionEntryTile({
    super.key,
    required this.entry,
    required this.reception,
    required this.onTap,
    this.padding,
  });
  final ReceptionEntry entry;
  final Reception reception;
  final VoidCallback onTap;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final sub = [
      if (entry.side != ReceptionDefaults.noSide) entry.side,
      formatTime(entry.createdAt),
      if (reception.mealTicketEnabled || entry.mealTickets > 0)
        '식권 ${entry.mealTickets}',
      if (reception.methodEnabled || entry.method == ReceptionDefaults.transfer)
        ReceptionDefaults.methodLabel(entry.method),
      if ((entry.memo ?? '').isNotEmpty) entry.memo!,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: padding ??
            const EdgeInsets.symmetric(
                horizontal: AppSpacing.page, vertical: AppSpacing.item),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name,
                      style: AppText.receptionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: AppText.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(formatWon(entry.amount),
                style: AppText.receptionName
                    .copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// 접수 항목 수정 · 삭제 창
Future<void> showReceptionEntryForm(
  BuildContext context, {
  required ReceptionEntry entry,
  required List<String> sides,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _EntryFormSheet(entry: entry, sides: sides),
  );
}

class _EntryFormSheet extends ConsumerStatefulWidget {
  const _EntryFormSheet({required this.entry, required this.sides});
  final ReceptionEntry entry;
  final List<String> sides;

  @override
  ConsumerState<_EntryFormSheet> createState() => _EntryFormSheetState();
}

class _EntryFormSheetState extends ConsumerState<_EntryFormSheet> {
  late final _name = TextEditingController(text: widget.entry.name);
  late final _amount =
      TextEditingController(text: formatNumber(widget.entry.amount));
  late final _memo = TextEditingController(text: widget.entry.memo ?? '');
  late String _side = widget.entry.side;
  late String _method = widget.entry.method;
  late int _meals = widget.entry.mealTickets;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _memo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final amount = parseAmount(_amount.text);
    if (name.isEmpty || amount <= 0) {
      showSnack(context, '이름과 금액을 입력해 주세요.');
      return;
    }
    final memo = _memo.text.trim();
    await ref.read(repositoryProvider).updateReceptionEntry(widget.entry
        .copyWith(
            name: name,
            amount: amount,
            side: _side,
            method: _method,
            mealTickets: _meals,
            memo: memo.isEmpty ? null : memo));
    ref.refreshData();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: '항목 삭제',
        message: '${widget.entry.name} 님의 항목을 삭제할까요?',
        okText: '삭제',
        destructive: true);
    if (!ok) return;
    await ref.read(repositoryProvider).deleteReceptionEntry(widget.entry.id);
    ref.refreshData();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final sides = {...widget.sides, widget.entry.side}.toList();
    return Padding(
      padding:
          EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('항목 수정', style: AppText.appTitle),
            const SizedBox(height: 16),
            TestId('entry_edit_name', child: TextField(
              controller: _name,
              style: AppText.receptionName,
              decoration: const InputDecoration(labelText: '이름'),
            )),
            const SizedBox(height: 16),
            TestId('entry_edit_amount', child: TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsFormatter()],
              style: AppText.receptionName,
              decoration:
                  const InputDecoration(labelText: '금액', suffixText: '원'),
            )),
            if (sides.length > 1) ...[
              const SizedBox(height: 16),
              const FieldLabel('구분'),
              ChoiceChips(
                options: sides,
                selected: _side,
                onSelected: (v) => setState(() => _side = v),
              ),
            ],
            const SizedBox(height: 16),
            ReceptionOptions(
              meals: _meals,
              method: _method,
              memo: _memo,
              onMeals: (v) => setState(() => _meals = v),
              onMethod: (v) => setState(() => _method = v),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: AppSpacing.receptionButton,
              child: TestId('entry_edit_save', child: FilledButton(onPressed: _save, child: const Text('저장'))),
            ),
            const SizedBox(height: 8),
            TestId('entry_edit_delete', child: TextButton(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('이 항목 삭제'),
            )),
          ],
        ),
      ),
    );
  }
}

/// 식권 수 · 현금/계좌이체 · 메모 입력 묶음
class ReceptionOptions extends StatelessWidget {
  const ReceptionOptions({
    super.key,
    required this.meals,
    required this.method,
    required this.memo,
    required this.onMeals,
    required this.onMethod,
  });
  final int meals;
  final String method;
  final TextEditingController memo;
  final ValueChanged<int> onMeals;
  final ValueChanged<String> onMethod;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Text('식권 수', style: AppText.receptionName)),
            IconButton.outlined(
              tooltip: '식권 줄이기',
              iconSize: 24,
              onPressed: meals > 0 ? () => onMeals(meals - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 48,
              child: Text('$meals',
                  textAlign: TextAlign.center, style: AppText.summaryAmount),
            ),
            IconButton.outlined(
              tooltip: '식권 늘리기',
              iconSize: 24,
              onPressed: () => onMeals(meals + 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ReceptionDefaults.cash, label: Text('현금')),
            ButtonSegment(
                value: ReceptionDefaults.transfer, label: Text('계좌이체')),
          ],
          selected: {method},
          onSelectionChanged: (s) => onMethod(s.first),
        ),
        const SizedBox(height: 12),
        TestId('entry_edit_memo', child: TextField(
          controller: memo,
          decoration: const InputDecoration(labelText: '메모 (선택)'),
        )),
      ],
    );
  }
}

/// 이름 검색 창: "아까 김민수 님 적었나?" 확인용. 항목을 누르면 수정.
Future<void> showReceptionSearch(
  BuildContext context, {
  required String receptionId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _SearchSheet(receptionId: receptionId),
  );
}

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet({required this.receptionId});
  final String receptionId;

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final package =
        ref.watch(receptionPackageProvider(widget.receptionId)).value;
    final q = _query.text.trim();
    final results = q.isEmpty
        ? const <ReceptionEntry>[]
        : (package?.entries ?? const <ReceptionEntry>[])
            .where((e) => e.name.contains(q))
            .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.page, 0, AppSpacing.page, 12),
            child: TestId('entry_search_input', child: TextField(
              controller: _query,
              autofocus: true,
              style: AppText.receptionName,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '이름 검색',
                prefixIcon: Icon(Icons.search),
              ),
            )),
          ),
          Flexible(
            child: results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.page, 12, AppSpacing.page, 32),
                    child: Text(q.isEmpty ? '찾을 이름을 입력해 주세요.' : '접수 기록이 없어요.',
                        textAlign: TextAlign.center, style: AppText.body),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final e in results)
                        ReceptionEntryTile(
                          entry: e,
                          reception: package!.reception,
                          onTap: () => showReceptionEntryForm(context,
                              entry: e, sides: package.sides),
                        ),
                      const SizedBox(height: 20),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
