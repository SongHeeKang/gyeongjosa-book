import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/amount_input.dart';
import '../widgets/common.dart';
import '../widgets/reception_entry_sheet.dart';
import 'reception_summary_screen.dart';

/// 접수 화면: 이름 입력 → 금액 버튼 탭(바로 저장) → 다음 손님.
/// 인터넷 없이 동작하고, 이 화면에서는 결제 화면을 절대 띄우지 않는다.
class ReceptionScreen extends ConsumerStatefulWidget {
  const ReceptionScreen({super.key, required this.receptionId});
  final String receptionId;

  @override
  ConsumerState<ReceptionScreen> createState() => _ReceptionScreenState();
}

class _ReceptionScreenState extends ConsumerState<ReceptionScreen> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _memo = TextEditingController();
  String? _side;
  String _method = ReceptionDefaults.cash;
  int _meals = 1;
  bool _showOptions = false;
  bool _saving = false;
  bool _nameMissing = false;

  @override
  void initState() {
    super.initState();
    _setWakelock(true);
  }

  @override
  void dispose() {
    _setWakelock(false);
    _name.dispose();
    _nameFocus.dispose();
    _memo.dispose();
    super.dispose();
  }

  Future<void> _setWakelock(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (e) {
      // 화면 켜짐 유지에 실패해도 접수는 계속할 수 있어야 한다.
      debugPrint('화면 켜짐 유지 실패: $e');
    }
  }

  String _currentSide(Reception reception) {
    final side = _side;
    if (side != null && reception.sides.contains(side)) return side;
    final saved = ref
        .read(prefsProvider)
        .getString(PrefKeys.receptionLastSide(reception.id));
    return saved != null && reception.sides.contains(saved)
        ? saved
        : reception.sides.first;
  }

  void _selectSide(Reception reception, String side) {
    setState(() => _side = side);
    ref
        .read(prefsProvider)
        .setString(PrefKeys.receptionLastSide(reception.id), side);
  }

  /// 이름이 비어 있으면 알려주고 false
  bool _checkName() {
    if (_name.text.trim().isNotEmpty) return true;
    setState(() => _nameMissing = true);
    _nameFocus.requestFocus();
    return false;
  }

  Future<void> _save(Reception reception, int amount) async {
    if (_saving || amount <= 0 || !_checkName()) return;
    setState(() => _saving = true);
    try {
      final memo = _memo.text.trim();
      await ref.read(repositoryProvider).insertReceptionEntry(ReceptionEntry(
            id: const Uuid().v4(),
            receptionId: reception.id,
            name: _name.text.trim(),
            amount: amount,
            side: _currentSide(reception),
            method: _method,
            mealTickets: _meals,
            memo: memo.isEmpty ? null : memo,
            createdAt: DateTime.now(),
          ));
      ref.refreshData();
      if (!mounted) return;
      setState(() {
        _name.clear();
        _memo.clear();
        _meals = 1;
        _method = ReceptionDefaults.cash;
        _showOptions = false;
      });
    } catch (e) {
      debugPrint('접수 저장 실패: $e');
      if (mounted) showSnack(context, '저장하지 못했어요. 다시 눌러 주세요.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _nameFocus.requestFocus();
      }
    }
  }

  Future<void> _enterAmount(Reception reception) async {
    if (!_checkName()) return;
    final amount = await showAmountDialog(context);
    if (amount != null) await _save(reception, amount);
  }

  Future<void> _undo(ReceptionEntry entry) async {
    await ref.read(repositoryProvider).deleteReceptionEntry(entry.id);
    ref.refreshData();
    if (mounted) showSnack(context, '${entry.name} 님 항목을 되돌렸어요.');
  }

  Future<void> _finish() async {
    await ref
        .read(repositoryProvider)
        .setReceptionFinished(widget.receptionId, finished: true);
    ref.refreshData();
    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
            builder: (_) =>
                ReceptionSummaryScreen(receptionId: widget.receptionId)));
  }

  Future<void> _confirmLeave() async {
    final leave = await confirmDialog(context,
        title: '접수를 잠시 멈출까요?',
        message: '입력한 내용은 저장되어 있어요.\n내 행사 탭에서 다시 들어오면 이어서 접수할 수 있어요.',
        okText: '멈추기');
    if (leave && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final package =
        ref.watch(receptionPackageProvider(widget.receptionId)).value;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('접수 중'),
          actions: [
            IconButton(
              tooltip: '이름 검색',
              icon: const Icon(Icons.search),
              onPressed: () => showReceptionSearch(context,
                  receptionId: widget.receptionId),
            ),
            TextButton(onPressed: _finish, child: const Text('접수 마치기')),
            const SizedBox(width: 8),
          ],
        ),
        body: package == null
            ? const Center(child: CircularProgressIndicator())
            : _body(package),
      ),
    );
  }

  Widget _body(ReceptionPackage package) {
    final reception = package.reception;
    final side = _currentSide(reception);
    final typed = _name.text.trim();
    final duplicate =
        typed.isNotEmpty && package.entries.any((e) => e.name == typed);
    final recent = package.entries.take(3).toList();

    return ListView(
      padding:
          const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 32),
      children: [
        _StatusHeader(package: package),
        const SizedBox(height: 14),
        if (reception.sides.length > 1) ...[
          _SideToggle(
            sides: reception.sides,
            selected: side,
            onSelected: (v) => _selectSide(reception, v),
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          controller: _name,
          focusNode: _nameFocus,
          autofocus: true,
          style: AppText.receptionInput,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _nameMissing = false),
          // 키보드의 완료를 눌러도 금액을 고를 수 있게 커서를 유지
          onSubmitted: (_) => _nameFocus.requestFocus(),
          decoration: InputDecoration(
            labelText: '이름',
            hintText: '손님 이름',
            errorText: _nameMissing ? '이름을 먼저 입력해 주세요' : null,
            helperText: duplicate ? '같은 이름이 있어요' : null,
            helperStyle: AppText.warning,
          ),
        ),
        const SizedBox(height: 12),
        const FieldLabel('금액을 누르면 바로 저장돼요'),
        for (var i = 0; i < ReceptionDefaults.amounts.length; i += 2) ...[
          Row(
            children: [
              _amountButton(reception, ReceptionDefaults.amounts[i]),
              const SizedBox(width: 10),
              _amountButton(reception, ReceptionDefaults.amounts[i + 1]),
            ],
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: AppSpacing.receptionButton,
          child: OutlinedButton(
            onPressed: _saving ? null : () => _enterAmount(reception),
            style:
                OutlinedButton.styleFrom(textStyle: AppText.receptionButton),
            child: const Text('직접 입력'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => setState(() => _showOptions = !_showOptions),
          icon: Icon(_showOptions ? Icons.expand_less : Icons.expand_more),
          label: Text(
              '식권 $_meals매 · ${ReceptionDefaults.methodLabel(_method)}${_memo.text.trim().isEmpty ? '' : ' · 메모'}'),
        ),
        if (_showOptions) ...[
          const SizedBox(height: 4),
          ReceptionOptions(
            meals: _meals,
            method: _method,
            memo: _memo,
            onMeals: (v) => setState(() => _meals = v),
            onMethod: (v) => setState(() => _method = v),
          ),
          const SizedBox(height: 8),
        ],
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 8),
          const AppDivider(),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                  child: Text('방금 입력', style: AppText.sectionTitle)),
              SizedBox(
                height: AppSpacing.receptionButton,
                child: OutlinedButton.icon(
                  onPressed: () => _undo(recent.first),
                  icon: const Icon(Icons.undo),
                  label: const Text('되돌리기'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final e in recent)
            ReceptionEntryTile(
              entry: e,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.item),
              onTap: () => showReceptionEntryForm(context,
                  entry: e, sides: package.sides),
            ),
        ],
      ],
    );
  }

  Widget _amountButton(Reception reception, int amount) => Expanded(
        child: SizedBox(
          height: AppSpacing.bigButton,
          child: FilledButton(
            onPressed: _saving ? null : () => _save(reception, amount),
            style: FilledButton.styleFrom(textStyle: AppText.receptionAmount),
            child: Text('${formatManWon(amount)}원'),
          ),
        ),
      );
}

/// 맨 위 현황: 행사 이름, 총 인원 · 총액, 구분별 소계
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.package});
  final ReceptionPackage package;

  @override
  Widget build(BuildContext context) {
    final totals = package.totals;
    final sides = package.sides;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(package.reception.title,
            style: AppText.sectionTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('${totals.count}명 · ${formatWon(totals.amount)}',
              style:
                  AppText.summaryAmount.copyWith(color: AppColors.primary)),
        ),
        if (sides.length > 1) ...[
          const SizedBox(height: 2),
          Text(
            [
              for (final s in sides)
                () {
                  final t = package.totalsFor(s);
                  return '$s ${t.count}명 ${formatWon(t.amount)}';
                }(),
            ].join('  ·  '),
            style: AppText.sub,
          ),
        ],
      ],
    );
  }
}

/// 구분 선택. 2개까지는 큰 토글, 그보다 많으면 줄바꿈되는 칩.
class _SideToggle extends StatelessWidget {
  const _SideToggle({
    required this.sides,
    required this.selected,
    required this.onSelected,
  });
  final List<String> sides;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (sides.length > 2) {
      return ChoiceChips(
          options: sides, selected: selected, onSelected: onSelected);
    }
    return SizedBox(
      height: AppSpacing.receptionButton,
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        expandedInsets: EdgeInsets.zero,
        segments: [
          for (final s in sides)
            ButtonSegment(
                value: s,
                label: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onSelected(s.first),
      ),
    );
  }
}
