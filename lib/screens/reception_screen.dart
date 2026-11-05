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

/// 접수 화면: 이름 입력 → 금액 버튼 탭(바로 저장) 또는 금액 입력 후 저장 → 다음 손님.
/// 인터넷 없이 동작하고, 이 화면에서는 결제 화면을 절대 띄우지 않는다.
class ReceptionScreen extends ConsumerStatefulWidget {
  const ReceptionScreen({super.key, required this.receptionId});
  final String receptionId;

  @override
  ConsumerState<ReceptionScreen> createState() => _ReceptionScreenState();
}

class _ReceptionScreenState extends ConsumerState<ReceptionScreen> {
  /// 금액칸에 만원 단위로 넣을 수 있는 한도 (더 큰 금액은 항목을 눌러 수정)
  static const _maxTypedAmount = 10000000;

  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _amount = TextEditingController();
  final _amountFocus = FocusNode();
  String? _side;

  /// 이번 손님만 기본과 다르게 고른 식권 수. 저장하면 다시 기본값으로.
  int? _mealsPicked;

  /// 이번 손님만 계좌이체. 저장하면 다시 현금으로.
  bool _transfer = false;
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
    _amount.dispose();
    _amountFocus.dispose();
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
      await ref.read(repositoryProvider).insertReceptionEntry(ReceptionEntry(
            id: const Uuid().v4(),
            receptionId: reception.id,
            name: _name.text.trim(),
            amount: amount,
            side: _currentSide(reception),
            method: reception.methodEnabled && _transfer
                ? ReceptionDefaults.transfer
                : ReceptionDefaults.cash,
            mealTickets: reception.mealTicketEnabled
                ? _mealsPicked ?? reception.defaultMealTickets
                : 0,
            createdAt: DateTime.now(),
          ));
      ref.refreshData();
      if (!mounted) return;
      setState(() {
        _name.clear();
        _amount.clear();
        _mealsPicked = null;
        _transfer = false;
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

  /// 금액칸에 적은 금액으로 저장. 이름이 비어 있으면 금액은 그대로 두고 이름칸으로 간다.
  Future<void> _saveTyped(Reception reception) async {
    final amount = parseManWon(_amount.text);
    if (amount <= 0) {
      _amountFocus.requestFocus();
      return;
    }
    // 70000처럼 원 단위로 치면 7억 원이 되므로 저장하지 않고 알려준다.
    if (amount >= _maxTypedAmount) {
      showSnack(context, '금액은 만원 단위로 입력해요. 7 → 70,000원');
      _amountFocus.requestFocus();
      return;
    }
    await _save(reception, amount);
  }

  /// 접수 중에도 식권 기록을 켜거나 끌 수 있다. 이미 저장한 항목은 그대로 둔다.
  Future<void> _toggleMeals(Reception reception) async {
    await ref.read(repositoryProvider).setReceptionMealTicketEnabled(
        reception.id, !reception.mealTicketEnabled);
    ref.refreshData();
    if (mounted) setState(() => _mealsPicked = null);
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
          reception: reception,
          entries: entries,
          duplicateTyped: duplicate,
          onUndo: () => _undo(entries.first),
        ),
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
                    onToggleMeals: () => _toggleMeals(reception),
                  )
                else ...[
                  _StatusHeader(
                    package: package,
                    onToggleMeals: () => _toggleMeals(reception),
                  ),
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
                TextField(
                  controller: _name,
                  focusNode: _nameFocus,
                  autofocus: true,
                  style: AppText.receptionInput,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _nameMissing = false),
                  // 키보드의 다음을 누르면 금액칸으로 간다
                  onEditingComplete: _amountFocus.requestFocus,
                  decoration: InputDecoration(
                    labelText: '이름',
                    hintText: '손님 이름',
                    errorText: _nameMissing ? '이름을 먼저 입력해 주세요' : null,
                  ),
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
                        reception: reception,
                        onTap: () => showReceptionEntryForm(context,
                            entry: e, sides: package.sides),
                      );
                    },
                  ),
          ),
          _AmountField(
            controller: _amount,
            focusNode: _amountFocus,
            onSave: () => _saveTyped(reception),
            meals: reception.mealTicketEnabled
                ? _mealsPicked ?? reception.defaultMealTickets
                : null,
            onMeals: (v) => setState(() => _mealsPicked = v),
            transfer: reception.methodEnabled ? _transfer : null,
            onTransfer: () => setState(() => _transfer = !_transfer),
          ),
          _AmountPad(onAmount: (a) => _save(reception, a)),
        ],
      ),
    );
  }
}

/// 금액 버튼 바로 위 줄: 만원 단위 금액칸 + 식권 칩 + 계좌 칩.
/// 키보드의 완료를 누르면 저장된다. 칩까지 한 줄에 안 들어가는 폰에서는 칩을 윗줄로 올린다.
class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.focusNode,
    required this.onSave,
    required this.meals,
    required this.onMeals,
    required this.transfer,
    required this.onTransfer,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSave;

  /// 식권 기록을 끄면 null
  final int? meals;
  final ValueChanged<int> onMeals;

  /// 결제 방법 구분을 끄면 null
  final bool? transfer;
  final VoidCallback onTransfer;

  static const _chipWidth = 34.0;
  static const _chipGap = 3.0;
  static const _mealLabelWidth = 32.0;
  static const _transferWidth = 48.0;
  static const _minFieldWidth = 84.0;

  double get _chipsWidth =>
      (meals != null ? _mealLabelWidth + 5 * _chipWidth + 4 * _chipGap : 0) +
      (transfer != null ? _transferWidth : 0) +
      (meals != null && transfer != null ? 6 : 0);

  /// 4+는 누를 때마다 한 장씩 늘어난다.
  void _pickMeals(int value) {
    final current = meals!;
    onMeals(value == 4 && current >= 4 ? current + 1 : value);
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, double width) {
    return SizedBox(
      width: width,
      height: AppSpacing.padButton,
      child: OutlinedButton(
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: AppText.receptionChip,
          backgroundColor: selected ? AppColors.primarySoft : null,
          foregroundColor: selected ? AppColors.primary : AppColors.text,
          side: selected
              ? const BorderSide(color: AppColors.primary, width: 1.5)
              : const BorderSide(color: AppColors.divider),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _chips() {
    final current = meals;
    final paying = transfer;
    // 칩이 포커스를 가져가면 키보드가 닫히므로 포커스를 받지 않게 한다.
    return ExcludeFocus(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (current != null) ...[
            const SizedBox(
                width: _mealLabelWidth,
                child: Text('식권', style: AppText.label)),
            for (var count = 0; count <= 4; count++) ...[
              if (count > 0) const SizedBox(width: _chipGap),
              _chip(
                count < 4 ? '$count' : (current > 4 ? '$current' : '4+'),
                count < 4 ? current == count : current >= 4,
                () => _pickMeals(count),
                _chipWidth,
              ),
            ],
          ],
          if (current != null && paying != null) const SizedBox(width: 6),
          if (paying != null)
            _chip('계좌', paying, onTransfer, _transferWidth),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      inputFormatters: [ManWonFormatter()],
      style: AppText.receptionName,
      onEditingComplete: () {},
      onSubmitted: (_) => onSave(),
      decoration: const InputDecoration(
        hintText: '금액',
        suffixText: '만원',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 4),
      child: LayoutBuilder(builder: (context, constraints) {
        final chipsWidth = _chipsWidth;
        final sameLine = chipsWidth > 0 &&
            constraints.maxWidth - chipsWidth - 8 >= _minFieldWidth;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chipsWidth > 0 && !sameLine) ...[
              SizedBox(
                height: AppSpacing.padButton,
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _chips()),
              ),
              const SizedBox(height: 4),
            ],
            SizedBox(
              height: AppSpacing.padButton,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: field),
                  if (sameLine) ...[
                    const SizedBox(width: 8),
                    _chips(),
                  ],
                ],
              ),
            ),
          ],
        );
      }),
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
    required this.reception,
    required this.entries,
    required this.duplicateTyped,
    required this.onUndo,
  });
  final Reception reception;
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
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text:
                              '${latest.name} · ${formatManWon(latest.amount)} · '),
                      if (reception.mealTicketEnabled ||
                          latest.mealTickets > 0) ...[
                        TextSpan(
                          text: '식권 ${latest.mealTickets}',
                          // 기본 매수와 다르면 굵게 보여 실수를 알아채게 한다
                          style: latest.mealTickets !=
                                  reception.defaultMealTickets
                              ? const TextStyle(fontWeight: FontWeight.w700)
                              : null,
                        ),
                        const TextSpan(text: ' · '),
                      ],
                      if (latest.method == ReceptionDefaults.transfer)
                        const TextSpan(text: '계좌 · '),
                      TextSpan(text: formatTime(latest.createdAt)),
                    ]),
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
    required this.onToggleMeals,
  });
  final ReceptionPackage package;
  final String side;
  final ValueChanged<String> onSide;
  final VoidCallback onToggleMeals;

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
          _MealToggle(
              enabled: package.reception.mealTicketEnabled,
              onTap: onToggleMeals),
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

/// 현황 줄의 식권 기록 켜기/끄기
class _MealToggle extends StatelessWidget {
  const _MealToggle({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: TextButton(
        onPressed: onTap,
        child: Text(enabled ? '식권 끄기' : '식권 켜기'),
      ),
    );
  }
}

/// 맨 위 현황: 행사 이름, 총 인원 · 총액, 구분별 소계
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.package, required this.onToggleMeals});
  final ReceptionPackage package;
  final VoidCallback onToggleMeals;

  @override
  Widget build(BuildContext context) {
    final totals = package.totals;
    final sides = package.sides;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(package.reception.title,
                  style: AppText.sectionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            _MealToggle(
                enabled: package.reception.mealTicketEnabled,
                onTap: onToggleMeals),
          ],
        ),
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
