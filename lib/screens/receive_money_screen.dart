import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/gift_record.dart';
import '../models/person.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../services/limit_service.dart';
import '../services/limits.dart';
import '../services/receive_targets.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/amount_input.dart';
import '../widgets/amount_pad.dart';
import '../widgets/coach_mark.dart';
import '../widgets/common.dart';
import '../widgets/person_name_field.dart';
import '../widgets/reception_entry_sheet.dart';
import '../widgets/record_form_sheet.dart';
import '../widgets/screen_coach.dart';
import '../widgets/test_id.dart';
import 'reception_form_screen.dart';
import 'reception_summary_screen.dart';

/// 받은 돈 적기: 이름 입력 → 금액 버튼 탭(바로 저장) 또는 금액 입력 후 저장 → 다음 손님.
/// 내 행사와 다른 사람 행사(대신 받기)가 이 화면 하나를 같이 쓰고, 저장하는 곳만
/// [ReceiveTarget]에 따라 다르다. 대신 받기에서는 결제 화면을 절대 띄우지 않는다.
class ReceiveMoneyScreen extends ConsumerStatefulWidget {
  const ReceiveMoneyScreen({super.key, required this.target});
  final ReceiveTarget target;

  @override
  ConsumerState<ReceiveMoneyScreen> createState() => _ReceiveMoneyScreenState();
}

class _ReceiveMoneyScreenState extends ConsumerState<ReceiveMoneyScreen> {
  /// 키보드 위 금액 영역 · 제목줄 · 현황처럼 자동완성 목록이 쓰면 안 되는 높이
  static const _optionsReservedHeight = 360.0;

  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _amount = TextEditingController();
  final _amountFocus = FocusNode();
  String? _side;

  /// 내 행사에서 자동완성으로 고른 기존 사람
  Person? _person;

  /// 이번 손님만 기본과 다르게 고른 식권 수. 저장하면 다시 기본값으로.
  int? _mealsPicked;

  /// 이번 손님만 계좌이체. 저장하면 다시 현금으로.
  bool _transfer = false;
  bool _saving = false;
  bool _nameMissing = false;
  bool _coachChecked = false;

  ReceiveTarget get _target => widget.target;

  @override
  void initState() {
    super.initState();
    _setWakelock(true);
    _name.addListener(() {
      // 고른 뒤 이름을 고치면 연결 해제
      if (_person != null && _name.text.trim() != _person!.name) {
        setState(() => _person = null);
      }
    });
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
      // 화면 켜짐 유지에 실패해도 계속 적을 수 있어야 한다.
      debugPrint('화면 켜짐 유지 실패: $e');
    }
  }

  /// 도움말은 두 경우 모두 첫 저장 전에만 자동으로 띄운다.
  Future<void> _showFirstCoach() async {
    if (!mounted) return;
    final shown = await showCoachOnce(
        context, ref.read(prefsProvider), CoachScreen.receiveMoney);
    if (shown && mounted) _nameFocus.requestFocus();
  }

  String _currentSide(ReceiveSnapshot s) {
    final side = _side;
    if (side != null && s.sides.contains(side)) return side;
    final saved = ref.read(prefsProvider).getString(_target.sidePrefKey);
    return saved != null && s.sides.contains(saved) ? saved : s.sides.first;
  }

  void _selectSide(String side) {
    setState(() => _side = side);
    ref.read(prefsProvider).setString(_target.sidePrefKey, side);
  }

  /// 이름이 비어 있으면 알려주고 false
  bool _checkName() {
    if (_name.text.trim().isNotEmpty) return true;
    setState(() => _nameMissing = true);
    _nameFocus.requestFocus();
    return false;
  }

  Future<void> _save(ReceiveSnapshot s, int amount) async {
    if (_saving || amount <= 0 || !_checkName()) return;
    setState(() => _saving = true);
    var saved = false;
    try {
      saved = await _target.save(
          context,
          ref,
          ReceiveInput(
            name: _name.text.trim(),
            amount: amount,
            side: _currentSide(s),
            transfer: s.methodEnabled && _transfer,
            mealTickets: s.mealTicketEnabled
                ? _mealsPicked ?? s.defaultMealTickets
                : null,
            person: _person,
          ));
      if (!mounted) return;
      if (saved) {
        setState(() {
          _name.clear();
          _amount.clear();
          _person = null;
          _mealsPicked = null;
          _transfer = false;
        });
      } else if (parseAmount(_amount.text) != amount) {
        // 결제 화면을 닫았으면 적은 이름과 금액을 그대로 둔다
        _amount.text = formatNumber(amount);
      }
    } catch (e) {
      debugPrint('받은 돈 저장 실패: $e');
      if (mounted) showSnack(context, '저장하지 못했어요. 다시 눌러 주세요.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _nameFocus.requestFocus();
      }
    }
  }

  /// 금액칸에 적은 금액으로 저장. 이름이 비어 있으면 금액은 그대로 두고 이름칸으로 간다.
  Future<void> _saveTyped(ReceiveSnapshot s) async {
    final amount = parseAmount(_amount.text);
    if (amount <= 0) {
      _amountFocus.requestFocus();
      return;
    }
    await _save(s, amount);
  }

  /// 최근 저장 한 줄: 식권 매수(기본과 다르면 굵게)와 계좌 여부를 함께 보여준다.
  RecentSavedItem _recentItem(ReceiveSnapshot s, ReceiveItem e) =>
      RecentSavedItem(
        id: e.id,
        name: e.name,
        amount: e.amount,
        savedAt: e.savedAt,
        details: [
          if (s.mealTicketEnabled || e.mealTickets > 0)
            TextSpan(
              text: '식권 ${e.mealTickets}',
              style: e.mealTickets != s.defaultMealTickets
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : null,
            ),
          if (e.method == ReceptionDefaults.transfer)
            const TextSpan(text: '계좌'),
        ],
      );

  Future<void> _toggleMeals(ReceiveSnapshot s) async {
    await _target.setMealTicketEnabled(ref, !s.mealTicketEnabled);
    if (mounted) setState(() => _mealsPicked = null);
  }

  /// 내 행사의 받기 설정(구분 · 식권 · 결제 방법)을 바꾼다.
  Future<void> _openSettings() async {
    final target = _target;
    if (target is! MyEventTarget) return;
    final event = await ref.read(repositoryProvider).getEvent(target.eventId);
    if (event == null || !mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) =>
                ReceptionFormScreen.myEvent(event: event, editing: true)));
    if (mounted) _nameFocus.requestFocus();
  }

  Future<void> _undo(ReceiveItem item) async {
    await _target.undo(ref, item);
    if (mounted) showSnack(context, '${item.name} 님 항목을 되돌렸어요.');
  }

  Future<void> _edit(ReceiveSnapshot s, ReceiveItem item) async {
    final source = item.source;
    if (source is ReceptionEntry) {
      await showReceptionEntryForm(context, entry: source, sides: s.allSides);
    } else if (source is GiftRecord) {
      final target = _target as MyEventTarget;
      final event = await ref.read(repositoryProvider).getEvent(target.eventId);
      if (!mounted) return;
      await showRecordForm(context,
          personId: source.personId, existing: source, event: event);
    }
  }

  Future<void> _finish() async {
    final target = _target;
    switch (target) {
      case MyEventTarget():
        Navigator.pop(context);
      case ReceptionTarget(:final receptionId):
        await ref
            .read(repositoryProvider)
            .setReceptionFinished(receptionId, finished: true);
        ref.refreshData();
        if (!mounted) return;
        Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(
                builder: (_) =>
                    ReceptionSummaryScreen(receptionId: receptionId)));
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await confirmDialog(context,
        title: '받은 돈 적기를 잠시 멈출까요?',
        message: '입력한 내용은 저장되어 있어요.\n내 행사 탭에서 다시 들어오면 이어서 적을 수 있어요.',
        okText: '멈추기');
    if (leave && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _target.watch(ref);
    if (snapshot != null && !_coachChecked) {
      _coachChecked = true;
      if (snapshot.items.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showFirstCoach());
      }
    }
    final target = _target;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('받은 돈 적기'),
          actions: [
            if (target is ReceptionTarget)
              TestId('entry_search', child: IconButton(
                tooltip: '이름 검색',
                icon: const Icon(Icons.search),
                onPressed: () => showReceptionSearch(context,
                    receptionId: target.receptionId),
              )),
            if (target is ReceptionTarget)
              TestId('btn_finish', child: TextButton(
                  onPressed: _finish, child: const Text('받기 끝내기')))
            else
              TestId('btn_done', child: TextButton(
                  onPressed: _finish, child: const Text('완료'))),
            const SizedBox(width: 8),
          ],
        ),
        body: snapshot == null
            ? const Center(child: CircularProgressIndicator())
            : _body(snapshot),
      ),
    );
  }

  Widget _body(ReceiveSnapshot s) {
    final side = _currentSide(s);
    final typed = _name.text.trim();
    final items = s.items;
    final duplicate = typed.isNotEmpty && items.any((e) => e.name == typed);
    // 키보드가 열려 있으면 바쁜 때: 현황을 한 줄로 줄이고 전체 내역은 숨긴다.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // 화면이 낮은 폰에서는 키보드가 없어도 현황을 한 줄로 줄인다.
    final compactStatus = keyboardOpen || isShortScreen(context);
    final tight = isAmountAreaTight(context);
    final place = _Place(label: '${_target.placeLabel} · ${s.title}');
    final status = _StatusControls(
      snapshot: s,
      side: side,
      onSide: _selectSide,
      onToggleMeals: () => _toggleMeals(s),
      onSettings: _target is MyEventTarget ? _openSettings : null,
      onHelpClosed: _nameFocus.requestFocus,
    );

    // 저장 전에도 도움말이 가리킬 수 있게 비어 있으면 한 줄 자리를 잡아 둔다.
    Widget recentSaved(int lines) => items.isEmpty && !duplicate
        ? Padding(
            padding: const EdgeInsets.only(top: 10),
            child: CoachTarget(
              spot: CoachSpot.receiveRecent,
              child: SizedBox(height: recentLineHeight(context)),
            ),
          )
        : CoachTarget(
            spot: CoachSpot.receiveRecent,
            child: RecentSavedList(
              items: [for (final e in items.take(lines + 1)) _recentItem(s, e)],
              lines: lines,
              warn: duplicate ||
                  (items.isNotEmpty &&
                      items.where((e) => e.name == items.first.name).length >
                          1),
              onUndo: items.isEmpty ? () {} : () => _undo(items.first),
            ),
          );

    final people = _target.isMine
        ? ref.watch(allPeopleProvider).value ?? const <Person>[]
        : null;
    final nameField = people != null
        ? PersonNameField(
            controller: _name,
            focusNode: _nameFocus,
            people: people,
            autofocus: true,
            hintText: '손님 이름',
            helperText: _person != null
                ? '기존 사람(${_person!.relation})에 연결돼요'
                : null,
            errorText: _nameMissing ? '이름을 먼저 입력해 주세요' : null,
            // 자동완성 목록이 아래 금액 버튼을 가리지 않게
            optionsMaxHeight: (MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom -
                    MediaQuery.paddingOf(context).vertical -
                    _optionsReservedHeight)
                .clamp(72.0, 280.0),
            onEditingComplete: _amountFocus.requestFocus,
            onSelected: (p) => setState(() => _person = p),
            onChanged: () => setState(() => _nameMissing = false),
          )
        : TextField(
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
          );

    return SafeArea(
      top: false,
      child: EntryLayout(
        top: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compactStatus)
                TestId('reception_status',
                    child: _CompactStatus(
                        snapshot: s, place: place, controls: status))
              else ...[
                TestId('reception_status',
                    child: _StatusHeader(
                        snapshot: s, place: place, controls: status)),
                const SizedBox(height: 12),
                if (s.sides.length > 1) ...[
                  TestId('toggle_side',
                      child: _SideToggle(
                        sides: s.sides,
                        selected: side,
                        onSelected: _selectSide,
                      )),
                  const SizedBox(height: 12),
                ],
              ],
              // 내 행사: 무료 30명이 거의 찼으면 미리 알려준다 (추가 M)
              if (_target.isMine)
                if (ref.watch(remainingPeopleProvider).value case final free?
                    when free <= 5)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: TestId(
                      'free_remaining',
                      child: Text(
                        free > 0
                            ? '무료로 $free명 더 적을 수 있어요'
                            : '무료 ${FreeLimits.people}명이 다 찼어요. 이미 등록한 사람은 계속 적을 수 있어요',
                        style: AppText.sub,
                      ),
                    ),
                  ),
              TestId('input_guest_name', child: nameField),
            ],
          ),
        ),
        list: keyboardOpen
            // 최근 저장은 3줄, 화면이 작은 폰에서는 들어가는 만큼만
            ? LayoutBuilder(
                builder: (_, constraints) => ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                  children: [
                    recentSaved(((constraints.maxHeight -
                                recentWarningHeight(context)) /
                            recentLineHeight(context))
                        .floor()
                        .clamp(1, 3)),
                  ],
                ),
              )
            : TestId('entry_list',
                child: ListView.builder(
                  itemCount: items.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.page),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            recentSaved(1),
                            if (items.isNotEmpty) const AppDivider(),
                          ],
                        ),
                      );
                    }
                    final e = items[i - 1];
                    return TestId('entry_item_${i - 1}',
                        child: _ItemTile(
                          item: e,
                          snapshot: s,
                          onTap: () => _edit(s, e),
                        ));
                  },
                )),
        compactList: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: recentSaved(1),
        ),
        bottom: [
          AmountField(
            controller: _amount,
            focusNode: _amountFocus,
            onSave: () => _saveTyped(s),
            meals: s.mealTicketEnabled
                ? _mealsPicked ?? s.defaultMealTickets
                : null,
            onMeals: (v) => setState(() => _mealsPicked = v),
            transfer: s.methodEnabled ? _transfer : null,
            onTransfer: () => setState(() => _transfer = !_transfer),
            tight: tight,
          ),
          CoachTarget(
            spot: CoachSpot.receiveAmounts,
            child: AmountPad(
              onAmount: (a) => _save(s, a),
              buttonHeight:
                  tight ? AppSpacing.padButtonTight : AppSpacing.padButton,
            ),
          ),
        ],
      ),
    );
  }
}

/// 저장 위치: "내 행사 · 우리 결혼식" / "대신 받기 · 누나 결혼식"
class _Place extends StatelessWidget {
  const _Place({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return CoachTarget(
      spot: CoachSpot.receivePlace,
      child: TestId('receive_place',
          child: Text(label,
              style: AppText.sub.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis)),
    );
  }
}

/// 현황 줄의 버튼들: 식권 켜기/끄기, 구분 ▾(한 줄 현황에서만), 행사 설정(내 행사), 도움말
class _StatusControls {
  const _StatusControls({
    required this.snapshot,
    required this.side,
    required this.onSide,
    required this.onToggleMeals,
    required this.onSettings,
    required this.onHelpClosed,
  });
  final ReceiveSnapshot snapshot;
  final String side;
  final ValueChanged<String> onSide;
  final VoidCallback onToggleMeals;
  final VoidCallback? onSettings;
  final VoidCallback onHelpClosed;

  List<Widget> build({required bool withSideMenu}) {
    final sides = snapshot.sides;
    return [
      _MealToggle(enabled: snapshot.mealTicketEnabled, onTap: onToggleMeals),
      if (withSideMenu && sides.length > 1)
        MenuAnchor(
          builder: (context, controller, _) => TextButton(
            style: _compactButton,
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
      if (onSettings case final open?)
        ExcludeFocus(
          child: TestId('btn_receive_settings',
              child: IconButton(
                tooltip: '행사 설정',
                iconSize: 20,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 44),
                padding: EdgeInsets.zero,
                color: AppColors.icon,
                icon: const Icon(Icons.tune),
                onPressed: open,
              )),
        ),
      HelpButton(
          screen: CoachScreen.receiveMoney, size: 20, onClosed: onHelpClosed),
    ];
  }
}

/// 키보드가 열려 있을 때의 현황 한 줄: 인원 · 총액 · 저장 위치 · 구분 ▾
class _CompactStatus extends StatelessWidget {
  const _CompactStatus({
    required this.snapshot,
    required this.place,
    required this.controls,
  });
  final ReceiveSnapshot snapshot;
  final Widget place;
  final _StatusControls controls;

  @override
  Widget build(BuildContext context) {
    final total = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text('${snapshot.count}명 · ${formatWon(snapshot.total)}',
          style: AppText.sectionTitle.copyWith(color: AppColors.primary)),
    );
    final buttons = controls.build(withSideMenu: true);
    final summary = Row(children: [
      Flexible(child: total),
      const SizedBox(width: 8),
      Expanded(child: place),
    ]);
    // 좁은 폰에서 한 줄에 다 넣으면 총액 글자가 아주 작아지므로 두 줄로 나눈다.
    if (isNarrowScreen(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.only(top: 6), child: summary),
          SizedBox(
            height: 44,
            child: Row(children: [
              // 글자를 크게 키운 좁은 폰에서는 버튼 글자를 조금 줄여서라도 한 줄에 넣는다
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [...buttons.take(buttons.length - 1)]),
                ),
              ),
              buttons.last,
            ]),
          ),
        ],
      );
    }
    // 총액 아래에 저장 위치를 작게 겹쳐 놓아, 버튼이 많아도 저장 위치가 잘리지 않게 한다.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [total, place],
          ),
        ),
        ...buttons,
      ]),
    );
  }
}

/// 현황 줄 버튼: 저장 위치 글자가 잘리지 않게 좌우 여백을 줄인다 (누르는 높이 44는 그대로)
final _compactButton = TextButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: 6),
  minimumSize: const Size(44, 44),
);

/// 현황 줄의 식권 기록 켜기/끄기
class _MealToggle extends StatelessWidget {
  const _MealToggle({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: TestId('toggle_meal', child: TextButton(
        onPressed: onTap,
        style: _compactButton,
        child: Text(enabled ? '식권 끄기' : '식권 켜기'),
      )),
    );
  }
}

/// 맨 위 현황: 저장 위치, 총 인원 · 총액, 구분별 소계
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.snapshot,
    required this.place,
    required this.controls,
  });
  final ReceiveSnapshot snapshot;
  final Widget place;
  final _StatusControls controls;

  @override
  Widget build(BuildContext context) {
    final sides = snapshot.allSides;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: place),
            ...controls.build(withSideMenu: false),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('${snapshot.count}명 · ${formatWon(snapshot.total)}',
              style: AppText.summaryAmount.copyWith(color: AppColors.primary)),
        ),
        if (sides.length > 1) ...[
          const SizedBox(height: 2),
          Text(
            [
              for (final s in sides)
                () {
                  final t = snapshot.totalsFor(s);
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

/// 전체 내역 한 줄: 이름 / 구분 · 시각 · 식권 · 방법 · 메모 / 금액
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.snapshot,
    required this.onTap,
  });
  final ReceiveItem item;
  final ReceiveSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final source = item.source;
    final memo = switch (source) {
      ReceptionEntry(:final memo) => memo,
      GiftRecord(:final memo) => memo,
      _ => null,
    };
    final sub = [
      if (item.side != ReceptionDefaults.noSide) item.side,
      if (item.savedAt case final at?) formatTime(at),
      if (snapshot.mealTicketEnabled || item.mealTickets > 0)
        '식권 ${item.mealTickets}',
      if (snapshot.methodEnabled || item.method == ReceptionDefaults.transfer)
        ReceptionDefaults.methodLabel(item.method),
      if ((memo ?? '').isNotEmpty) memo!,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page, vertical: AppSpacing.item),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: AppText.receptionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub,
                        style: AppText.sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(formatWon(item.amount),
                    style: AppText.receptionName
                        .copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
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
