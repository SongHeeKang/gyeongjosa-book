import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    // 키보드가 열려 있으면 바쁜 때: 현황을 한 줄로 줄이고 전체 내역은 숨긴다.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final entries = package.entries;

    final inputExtras = <Widget>[
      if (entries.isNotEmpty || duplicate)
        _SavedLine(
          entries: entries,
          duplicateTyped: duplicate,
          onUndo: () => _undo(entries.first),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _showOptions = !_showOptions),
          icon: Icon(_showOptions ? Icons.expand_less : Icons.expand_more),
          label: Text(
              '식권 $_meals매 · ${ReceptionDefaults.methodLabel(_method)}${_memo.text.trim().isEmpty ? '' : ' · 메모'}'),
        ),
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
    ];

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (keyboardOpen)
                  _CompactStatus(
                    package: package,
                    side: side,
                    onSide: (v) => _selectSide(reception, v),
                  )
                else ...[
                  _StatusHeader(package: package),
                  const SizedBox(height: 12),
                  if (reception.sides.length > 1) ...[
                    _SideToggle(
                      sides: reception.sides,
                      selected: side,
                      onSelected: (v) => _selectSide(reception, v),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        focusNode: _nameFocus,
                        autofocus: true,
                        style: AppText.receptionInput,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() => _nameMissing = false),
                        // 키보드의 완료를 눌러도 키보드를 닫지 않고 금액을 고르게 한다
                        onSubmitted: (_) => _nameFocus.requestFocus(),
                        decoration: InputDecoration(
                          labelText: '이름',
                          hintText: '손님 이름',
                          errorText: _nameMissing ? '이름을 먼저 입력해 주세요' : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: AppSpacing.receptionButton,
                      child: OutlinedButton(
                        onPressed: () => _enterAmount(reception),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12)),
                        child: const Text('직접 입력'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: keyboardOpen
                ? ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.page),
                    children: inputExtras,
                  )
                : ListView.builder(
                    itemCount: entries.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.page),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ...inputExtras,
                              if (entries.isNotEmpty) const AppDivider(),
                            ],
                          ),
                        );
                      }
                      final e = entries[i - 1];
                      return ReceptionEntryTile(
                        entry: e,
                        onTap: () => showReceptionEntryForm(context,
                            entry: e, sides: package.sides),
                      );
                    },
                  ),
          ),
          _AmountPad(onAmount: (a) => _save(reception, a)),
        ],
      ),
    );
  }
}

/// 금액 버튼 8개(4개씩 2줄). 키보드 바로 위에 붙고, 누르면 짧게 진동한다.
class _AmountPad extends StatelessWidget {
  const _AmountPad({required this.onAmount});
  final ValueChanged<int> onAmount;

  @override
  Widget build(BuildContext context) {
    const perRow = 4;
    const amounts = ReceptionDefaults.amounts;
    Widget button(int amount) => Expanded(
          child: FilledButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              onAmount(amount);
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, AppSpacing.padButton),
              maximumSize: const Size(double.infinity, AppSpacing.padButton),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: AppText.receptionAmount,
            ),
            child: Text(formatManWon(amount)),
          ),
        );
    // 버튼이 포커스를 가져가면 키보드가 닫히므로 포커스를 받지 않게 한다.
    return ExcludeFocus(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, 4, AppSpacing.page, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < amounts.length; i += perRow) ...[
              if (i > 0) const SizedBox(height: 8),
              Row(
                children: [
                  for (var j = i; j < i + perRow; j++) ...[
                    if (j > i) const SizedBox(width: 8),
                    button(amounts[j]),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 방금 저장 한 줄: ✓ 이름 · 금액 · 저장 시각 + 되돌리기. 같은 이름 경고도 여기에 표시한다.
class _SavedLine extends StatelessWidget {
  const _SavedLine({
    required this.entries,
    required this.duplicateTyped,
    required this.onUndo,
  });
  final List<ReceptionEntry> entries;
  final bool duplicateTyped;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final latest = entries.isEmpty ? null : entries.first;
    final duplicateSaved = latest != null &&
        entries.where((e) => e.name == latest.name).length > 1;
    final warn = duplicateTyped || duplicateSaved;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          if (latest != null) ...[
            const Icon(Icons.check, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (latest != null)
                  Text(
                    '${latest.name} · ${formatManWon(latest.amount)} · ${formatTime(latest.createdAt)}',
                    style: AppText.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (warn) const Text('같은 이름이 있어요', style: AppText.warning),
              ],
            ),
          ),
          if (latest != null)
            TextButton(onPressed: onUndo, child: const Text('되돌리기')),
        ],
      ),
    );
  }
}

/// 키보드가 열려 있을 때의 현황 한 줄: 인원 · 총액 · 구분 ▾
class _CompactStatus extends StatelessWidget {
  const _CompactStatus({
    required this.package,
    required this.side,
    required this.onSide,
  });
  final ReceptionPackage package;
  final String side;
  final ValueChanged<String> onSide;

  @override
  Widget build(BuildContext context) {
    final totals = package.totals;
    final sides = package.reception.sides;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('${totals.count}명 · ${formatWon(totals.amount)}',
                  style: AppText.sectionTitle.copyWith(color: AppColors.primary)),
            ),
          ),
          if (sides.length > 1)
            MenuAnchor(
              builder: (context, controller, _) => TextButton(
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(side),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
              menuChildren: [
                for (final s in sides)
                  MenuItemButton(
                    onPressed: () => onSide(s),
                    child: Text(s, style: AppText.body),
                  ),
              ],
            ),
        ],
      ),
    );
  }
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
