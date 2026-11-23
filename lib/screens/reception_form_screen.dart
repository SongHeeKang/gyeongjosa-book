import '../widgets/unsaved_guard.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../services/limit_service.dart';
import '../services/notification_permission.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import 'event_actions.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/amount_input.dart';
import '../widgets/common.dart';
import '../services/receive_targets.dart';
import 'receive_money_screen.dart';

/// 행사 만들기 · 받기 설정.
/// - 행사 만들기([ReceptionFormScreen.new]): 맨 위에서 '누구 행사예요?'를 한 번만 고른다
///   (미리 고르지 않음, 필수). 이어서 행사 이름 · 종류 · 날짜 · 구분 · 식권 · 결제 방법,
///   다른 사람 행사면 받는 사람 이름도. [받기 시작]을 누르면
///   내 행사는 events에, 다른 사람 행사는 receptions에 저장하고 받은 돈 적기 화면으로 간다.
///   [내 행사]를 고르는 순간 내 행사 한도를 보고, 닿았으면 바로 결제 화면.
/// - 예전 내 행사의 받기 설정([ReceptionFormScreen.myEvent]): 구분, 식권, 결제 방법만.
///   받기 설정이 없는 예전 행사에서 처음 한 번 묻고, 받은 돈 적기 화면의 현황 줄에서
///   다시 바꿀 수 있다([editing]).
/// - 행사 수정([ReceptionFormScreen.edit], 추가 AA): 같은 화면을 '행사 수정'으로 연다.
///   지금 값이 채워져 있고 '누구 행사예요?'는 바꿀 수 없다. 구분은 한 줄씩 고치고,
///   손님이 있는 구분은 지울 수 없다. 맨 아래 [행사 삭제].
class ReceptionFormScreen extends ConsumerStatefulWidget {
  const ReceptionFormScreen({super.key, this.whose})
    : event = null,
      editing = false,
      editEvent = null,
      editReception = null,
      sideCounts = const {},
      guestCount = 0;

  const ReceptionFormScreen.myEvent({
    super.key,
    required Event this.event,
    this.editing = false,
  }) : whose = null,
       editEvent = null,
       editReception = null,
       sideCounts = const {},
       guestCount = 0;

  /// 행사 수정: 내 행사면 [editEvent], 다른 사람 행사면 [editReception].
  /// [sideCounts]는 구분별로 이미 적은 손님 수, [guestCount]는 전체 손님 수.
  const ReceptionFormScreen.edit({
    super.key,
    this.editEvent,
    this.editReception,
    this.sideCounts = const {},
    this.guestCount = 0,
  }) : whose = null,
       event = null,
       editing = false,
       assert(editEvent != null || editReception != null);

  /// 수정할 내 행사
  final Event? editEvent;

  /// 수정할 다른 사람 행사
  final Reception? editReception;

  /// 구분별 이미 적은 손님 수 (수정에서 손님이 있는 구분은 지울 수 없다)
  final Map<String, int> sideCounts;

  /// 이 행사의 손님 수 (삭제 확인 문구)
  final int guestCount;

  /// 행사 탭 묶음의 [+ 추가]로 열면 미리 골라 둔 '누구 행사예요?' (true: 내 행사, false: 다른 사람 행사)
  final bool? whose;

  /// 이미 있는 내 행사의 받기 설정이면 그 행사
  final Event? event;

  /// 이미 받고 있는 중에 설정만 바꾸는지 (저장 후 돌아간다)
  final bool editing;

  @override
  ConsumerState<ReceptionFormScreen> createState() =>
      _ReceptionFormScreenState();
}

class _ReceptionFormScreenState extends ConsumerState<ReceptionFormScreen> {
  final _title = TextEditingController();
  final _sides = TextEditingController();
  final _operator = TextEditingController();
  String _type = EventTypes.all.first;
  DateTime _date = DateTime.now();
  bool _saving = false;

  /// 식권 기록 여부와 결제 방법 구분은 미리 고르지 않고 반드시 고르게 한다.
  bool? _mealEnabled;
  int _defaultMeals = 1;
  bool? _methodEnabled;

  /// 행사 만들기에서 고른 '누구 행사예요?' (true: 내 행사, false: 다른 사람 행사, null: 아직)
  bool? _whose;

  bool get _isFuneral => _type == '장례';
  bool get _isWedding => _type == '결혼';

  /// 이미 있는 내 행사의 받기 설정만 바꾸는 화면
  bool get _settingsOnly => widget.event != null;

  /// 받는 사람 이름을 묻는지 (다른 사람 행사 만들기 · 수정)
  bool get _asksOperator => !_settingsOnly && _whose == false;

  /// 행사 수정 화면인지 (추가 AA)
  bool get _isEdit =>
      widget.editEvent != null || widget.editReception != null;

  /// 수정: 장소 · 메모 (내 행사만 저장할 곳이 있다)
  final _place = TextEditingController();
  final _memo = TextEditingController();

  /// 수정: 구분 한 줄씩. [_SideRow.original]이 있으면 원래 있던 구분.
  final _sideRows = <_SideRow>[];

  /// 처음 열었을 때의 값. 뒤로 갈 때 달라졌으면 작성 중 확인을 묻는다.
  late final String _initial;
  String get _snapshot => [
    _whose,
    _title.text,
    _type,
    _date,
    _sides.text,
    _operator.text,
    _mealEnabled,
    _defaultMeals,
    _methodEnabled,
    _place.text,
    _memo.text,
    for (final r in _sideRows) '${r.original}>${r.controller.text}',
  ].join('|');

  @override
  void initState() {
    super.initState();
    _whose = widget.whose;
    final event = widget.event;
    if (event != null) {
      _title.text = event.title;
      _date = event.date;
      if (EventTypes.all.contains(event.type)) _type = event.type;
      if (event.receiveSettingsDone) {
        _sides.text = event.sides
            .where((s) => s != ReceptionDefaults.noSide)
            .join(', ');
        _mealEnabled = event.mealTicketEnabled;
        _defaultMeals = event.defaultMealTickets;
        _methodEnabled = event.methodEnabled;
      }
    }
    _operator.text =
        ref.read(prefsProvider).getString(PrefKeys.receptionOperator) ?? '';
    _fillForEdit();
    _initial = _snapshot;
  }

  /// 행사 수정: 지금 값을 채운다.
  void _fillForEdit() {
    List<String> sides;
    if (widget.editEvent case final e?) {
      _whose = true;
      _title.text = e.title;
      _date = e.date;
      if (EventTypes.all.contains(e.type)) _type = e.type;
      _place.text = e.place ?? '';
      _memo.text = e.memo ?? '';
      sides = e.sides;
      // 받기 설정이 없는 예전 내 행사는 식권 · 결제 방법을 새로 고르게 둔다
      if (e.receiveSettingsDone) {
        _mealEnabled = e.mealTicketEnabled;
        _defaultMeals = e.defaultMealTickets;
        _methodEnabled = e.methodEnabled;
      }
    } else if (widget.editReception case final r?) {
      _whose = false;
      _title.text = r.title;
      _date = r.date;
      if (EventTypes.all.contains(r.eventType)) _type = r.eventType;
      _operator.text = r.operatorName;
      sides = r.sides;
      _mealEnabled = r.mealTicketEnabled;
      _defaultMeals = r.defaultMealTickets;
      _methodEnabled = r.methodEnabled;
    } else {
      return;
    }
    for (final side in sides) {
      if (side == ReceptionDefaults.noSide) continue;
      _sideRows.add(_SideRow(side));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _sides.dispose();
    _operator.dispose();
    _place.dispose();
    _memo.dispose();
    for (final r in _sideRows) {
      r.controller.dispose();
    }
    super.dispose();
  }

  /// 수정: 이 구분으로 이미 적은 손님 수
  int _countFor(String? side) =>
      side == null ? 0 : (widget.sideCounts[side] ?? 0);

  /// 수정: [저장]. 구분 이름을 바꾼 것은 이미 적은 손님에게도 반영한다.
  Future<void> _saveEdit() async {
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      showSnack(context, '행사 이름을 입력해 주세요.');
      return;
    }
    final names = <String>[];
    final renames = <String, String>{};
    for (final row in _sideRows) {
      final name = row.controller.text.trim();
      if (name.isEmpty) {
        // 손님이 있는 구분은 비울 수 없다(지운 것과 같아지므로)
        if (_countFor(row.original) > 0) {
          showSnack(context, "'${row.original}' 구분으로 적은 손님이 있어 이름을 비울 수 없어요.");
          return;
        }
        continue;
      }
      if (names.contains(name)) {
        showSnack(context, "같은 구분 이름 '$name'이 두 번 있어요.");
        return;
      }
      names.add(name);
      if (row.original != null && row.original != name) {
        renames[row.original!] = name;
      }
    }
    final sides = names.isEmpty ? const [ReceptionDefaults.noSide] : names;
    final repo = ref.read(repositoryProvider);
    setState(() => _saving = true);
    if (widget.editEvent case final e?) {
      final place = _place.text.trim();
      final memo = _memo.text.trim();
      final updated = Event(
        id: e.id,
        type: _type,
        title: title,
        date: _date,
        isMine: true,
        place: place.isEmpty ? null : place,
        memo: memo.isEmpty ? null : memo,
        notify: e.notify,
        personId: e.personId,
        pendingHidden: e.pendingHidden,
        receiveSides: sides,
        mealTicketEnabled: _mealEnabled!,
        defaultMealTickets: _defaultMeals,
        methodEnabled: _methodEnabled!,
      );
      await repo.updateMyEventInfo(updated, renames);
      // 날짜가 바뀌면 전날 알림도 새 날짜로
      await NotificationService.instance.scheduleForEvent(updated);
    } else if (widget.editReception case final r?) {
      final operatorName = _operator.text.trim();
      if (operatorName.isEmpty) {
        setState(() => _saving = false);
        showSnack(context, '받는 사람 이름을 입력해 주세요.');
        return;
      }
      await repo.updateReceptionInfo(
        Reception(
          id: r.id,
          title: title,
          eventType: _type,
          date: _date,
          sides: sides,
          operatorName: operatorName,
          startedAt: r.startedAt,
          finishedAt: r.finishedAt,
          mealTicketEnabled: _mealEnabled!,
          defaultMealTickets: _defaultMeals,
          methodEnabled: _methodEnabled!,
          imported: r.imported,
        ),
        renames,
      );
    }
    ref.refreshData();
    if (mounted) Navigator.pop(context);
  }

  /// 수정: [행사 삭제] (두 번 확인)
  Future<void> _delete() async {
    final deleted = widget.editEvent != null
        ? await deleteMyEventWithConfirm(
            context, ref, widget.editEvent!, widget.guestCount)
        : await deleteReceptionWithConfirm(
            context, ref, widget.editReception!.id, widget.guestCount);
    if (deleted && mounted) goToEventList(context, ref);
  }

  /// 수정: 구분 한 줄씩 (이름 고치기 · 지우기 · 추가)
  List<Widget> _sideEditor() => [
    const FieldLabel('구분'),
    if (_sideRows.isEmpty)
      const Padding(
        padding: EdgeInsets.only(bottom: 4),
        child: Text('구분 없이 받고 있어요', style: AppText.sub),
      ),
    for (final (i, row) in _sideRows.indexed) ...[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TestId(
              'input_side_${i + 1}',
              child: TextField(
                controller: row.controller,
                style: AppText.receptionName,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '구분 이름',
                  helperText: _countFor(row.original) > 0
                      ? '이 구분으로 적은 ${_countFor(row.original)}명이 있어요'
                      : null,
                ),
              ),
            ),
          ),
          TestId(
            'btn_side_delete_${i + 1}',
            child: IconButton(
              tooltip: '구분 지우기',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              // 손님이 있는 구분은 지울 수 없다
              onPressed: _countFor(row.original) > 0
                  ? null
                  : () => setState(() {
                      _sideRows.remove(row);
                      row.controller.dispose();
                    }),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ],
    Align(
      alignment: Alignment.centerLeft,
      child: TestId(
        'btn_side_add',
        child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => setState(() => _sideRows.add(_SideRow(null))),
          icon: const Icon(Icons.add),
          label: const Text('구분 추가'),
        ),
      ),
    ),
  ];

  void _selectType(String type) {
    setState(() {
      // 결혼을 벗어나면 신랑측 · 신부측만 빼고, 직접 적은 구분은 그대로 둔다.
      if (_isWedding && type != '결혼') {
        _sides.text = _parseSides()
            .where((s) => !ReceptionDefaults.weddingSides.contains(s))
            .join(', ');
      }
      _type = type;
    });
  }

  /// 신랑측 · 신부측 버튼. 입력칸의 내용을 바꾸므로 직접 적은 구분과 함께 쓸 수 있다.
  void _toggleWeddingSide(String side) {
    final picked = _parseSides();
    if (!picked.remove(side)) picked.add(side);
    const presets = ReceptionDefaults.weddingSides;
    setState(
      () => _sides.text = [
        ...presets.where(picked.contains),
        ...picked.where((s) => !presets.contains(s)),
      ].join(', '),
    );
  }

  /// 나란히 놓인 큰 선택 버튼 묶음
  /// 자동화 테스트용 식별자 (버튼 글자 → 이름)
  static const _testIds = {
    '신랑측': 'side_groom',
    '신부측': 'side_bride',
    '식권 기록 안 함': 'meal_off',
    '식권도 기록': 'meal_on',
    '1매': 'meal_default_1',
    '2매': 'meal_default_2',
    '현금만': 'method_cash_only',
    '계좌이체도 구분': 'method_split',
    '내 행사': 'whose_mine',
    '다른 사람 행사': 'whose_other',
  };

  Widget _choiceRow(List<(String, bool, VoidCallback?)> choices) {
    return Row(
      children: [
        for (var i = 0; i < choices.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: TestId(
              _testIds[choices[i].$1] ?? 'choice_${choices[i].$1}',
              selected: choices[i].$2,
              child: SizedBox(
                height: AppSpacing.receptionButton,
                child: OutlinedButton(
                  onPressed: choices[i].$3,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    backgroundColor: choices[i].$2
                        ? (choices[i].$3 == null
                              ? AppColors.divider
                              : AppColors.primarySoft)
                        : null,
                    foregroundColor: choices[i].$2 ? AppColors.primary : null,
                    disabledForegroundColor: AppColors.textSub,
                    side: choices[i].$2
                        ? BorderSide(
                            color: choices[i].$3 == null
                                ? AppColors.textSub
                                : AppColors.primary,
                            width: 1.5,
                          )
                        : null,
                  ),
                  child: Text(choices[i].$1),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _weddingSideButtons() {
    final picked = _parseSides();
    return _choiceRow([
      for (final side in ReceptionDefaults.weddingSides)
        (side, picked.contains(side), () => _toggleWeddingSide(side)),
    ]);
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

  List<String> _parseSides() => _sides.text
      .split(RegExp(r'[,，、]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();

  /// 내 행사: 받기 설정을 저장하고 받은 돈 적기 화면으로 (설정만 바꿀 때는 돌아간다)
  Future<void> _saveMyEvent(Event event) async {
    final sides = _parseSides();
    if (sides.isEmpty && _isFuneral) {
      showSnack(context, '상주 이름을 입력해 주세요.');
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(repositoryProvider)
        .updateEventReceiveSettings(
          event.withReceiveSettings(
            sides: sides.isEmpty ? const [ReceptionDefaults.noSide] : sides,
            mealTicketEnabled: _mealEnabled!,
            defaultMealTickets: _defaultMeals,
            methodEnabled: _methodEnabled!,
          ),
        );
    ref.refreshData();
    if (!mounted) return;
    if (widget.editing) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReceiveMoneyScreen(target: MyEventTarget(event.id!)),
      ),
    );
  }

  /// [내 행사]를 눌러 한도를 보는 중 (빠르게 두 번 눌러 결제 화면이 두 번 뜨지 않게)
  bool _checkingWhose = false;

  /// '누구 행사예요?' [내 행사]: 누르는 순간 한도를 본다.
  /// 결제 화면을 닫으면 '누구 행사예요?' 선택을 비운다.
  Future<void> _chooseWhose(bool mine) async {
    if (mine && _whose != true) {
      if (_checkingWhose) return;
      _checkingWhose = true;
      try {
        if (!await LimitService.canCreateMyEvent(context, ref)) {
          if (mounted) setState(() => _whose = null);
          return;
        }
      } finally {
        _checkingWhose = false;
      }
      if (!mounted) return;
    }
    setState(() => _whose = mine);
  }

  /// 새 내 행사를 만들고 받은 돈 적기로 간다.
  /// [_saving]은 [_start]가 먼저 켜 둔다(빠르게 여러 번 눌러도 한 번만 저장).
  Future<void> _createMyEvent(String title, List<String> sides) async {
    // 고른 뒤 다른 곳에서 내 행사가 생겼을 수 있어 한 번 더 본다
    if (!await LimitService.canCreateMyEvent(context, ref)) {
      return _stopSaving();
    }
    if (!mounted) return;
    final repo = ref.read(repositoryProvider);
    final newEvent = Event(
      type: _type,
      title: title,
      date: _date,
      isMine: true,
      notify: ref.read(notificationPermissionProvider),
      receiveSides: sides.isEmpty ? const [ReceptionDefaults.noSide] : sides,
      mealTicketEnabled: _mealEnabled!,
      defaultMealTickets: _defaultMeals,
      methodEnabled: _methodEnabled!,
    );
    // 저장 순간 안전장치: 한도를 넘으면 저장하지 않고 결제 화면
    final id = await LimitService.saveMyEvent(
      context,
      ref,
      (max) => repo.insertEvent(newEvent, maxMyEvents: max),
    );
    if (id == null) return _stopSaving();
    final event = await repo.getEvent(id);
    if (event != null) {
      await NotificationService.instance.scheduleForEvent(event);
    }
    ref.refreshData();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReceiveMoneyScreen(target: MyEventTarget(id)),
      ),
    );
  }

  void _stopSaving() {
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _start() async {
    if (widget.event case final event?) return _saveMyEvent(event);
    if (_saving) return;
    if (_whose == null) {
      showSnack(context, '누구 행사인지 골라 주세요.');
      return;
    }
    final title = _title.text.trim();
    if (title.isEmpty) {
      showSnack(context, '행사 이름을 입력해 주세요.');
      return;
    }
    final sides = _parseSides();
    if (sides.isEmpty && _isFuneral) {
      showSnack(context, '상주 이름을 입력해 주세요.');
      return;
    }
    if (_whose == true) {
      // 다음 프레임을 기다리지 않고 바로 막는다 (빠른 연속 누르기)
      _saving = true;
      setState(() {});
      return _createMyEvent(title, sides);
    }
    final operatorName = _operator.text.trim();
    if (operatorName.isEmpty) {
      showSnack(context, '받는 사람 이름을 입력해 주세요.');
      return;
    }
    setState(() => _saving = true);
    final reception = Reception(
      id: const Uuid().v4(),
      title: title,
      eventType: _type,
      date: _date,
      sides: sides.isEmpty ? const [ReceptionDefaults.noSide] : sides,
      operatorName: operatorName,
      startedAt: DateTime.now(),
      mealTicketEnabled: _mealEnabled!,
      defaultMealTickets: _defaultMeals,
      methodEnabled: _methodEnabled!,
    );
    await ref.read(repositoryProvider).insertReception(reception);
    await ref
        .read(prefsProvider)
        .setString(PrefKeys.receptionOperator, operatorName);
    ref.refreshData();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            ReceiveMoneyScreen(target: ReceptionTarget(reception.id)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
    isDirty: () => _snapshot != _initial,
    child: _buildForm(context),
  );

  Widget _buildForm(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEdit
              ? '행사 수정'
              : (_settingsOnly ? '행사 설정' : '행사 만들기'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          8,
          AppSpacing.page,
          32,
        ),
        children: [
          if (_settingsOnly) ...[
            Text('내 행사 · ${widget.event!.title}', style: AppText.sectionTitle),
            const SizedBox(height: 4),
            const Text(
              '이 행사에서 받을 때 쓸 설정이에요. 받는 중에도 바꿀 수 있어요.',
              style: AppText.sub,
            ),
            const SizedBox(height: 20),
          ] else ...[
            const FieldLabel('누구 행사예요?'),
            _choiceRow([
              ('내 행사', _whose == true, _isEdit ? null : () => _chooseWhose(true)),
              (
                '다른 사람 행사',
                _whose == false,
                _isEdit ? null : () => _chooseWhose(false),
              ),
            ]),
            const SizedBox(height: 6),
            if (_isEdit)
              Text(
                widget.editReception != null
                    ? '내 행사로 바꾸려면 행사 상세의 [내 행사로 바꾸기]'
                    : '누구 행사인지는 만든 뒤 바꿀 수 없어요',
                style: AppText.sub,
              )
            else
            Text(switch (_whose) {
              true => '받은 손님이 사람 탭에도 들어가요 · 받은 만큼 챙기기 · 통계',
              false => '장부에만 저장돼요(사람 탭에 안 들어감) · 끝나면 장부 보내기',
              null => '내 결혼식 · 돌잔치면 내 행사, 가족 · 친구 행사에서 받아 주면 다른 사람 행사',
            }, style: AppText.sub),
            const SizedBox(height: 20),
            TestId(
              'input_event_title',
              child: TextField(
                controller: _title,
                style: AppText.receptionName,
                decoration: InputDecoration(
                  labelText: '행사 이름',
                  hintText: _whose == true ? '예: 우리 결혼식' : '예: 누나 결혼식',
                ),
              ),
            ),
            const SizedBox(height: 20),
            const FieldLabel('종류'),
            ChoiceChips(
              testIdPrefix: 'select_event_type',
              options: EventTypes.all,
              selected: _type,
              onSelected: _selectType,
            ),
            const SizedBox(height: 20),
            TestId(
              'input_date',
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(formatDate(_date)),
              ),
            ),
            const SizedBox(height: 20),
            // 수정: 내 행사는 장소 · 메모도 고친다
            if (widget.editEvent != null) ...[
              TestId(
                'input_place',
                child: TextField(
                  controller: _place,
                  decoration: const InputDecoration(labelText: '장소 (선택)'),
                ),
              ),
              const SizedBox(height: 16),
              TestId(
                'input_memo',
                child: TextField(
                  controller: _memo,
                  decoration: const InputDecoration(labelText: '메모 (선택)'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
          if (_isEdit) ..._sideEditor(),
          if (!_isEdit && _isWedding) ...[
            const FieldLabel('구분'),
            _weddingSideButtons(),
            const SizedBox(height: 12),
          ],
          if (!_isEdit)
          TestId(
            'input_side',
            child: TextField(
              controller: _sides,
              style: AppText.receptionName,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _isFuneral
                    ? '상주 이름'
                    : _isWedding
                    ? '구분 직접 입력'
                    : '구분',
                // 입력칸을 누르기 전에도 예시가 보이도록 제목을 위에 고정한다
                floatingLabelBehavior: FloatingLabelBehavior.always,
                hintText: _isFuneral ? '예: 홍길동, 홍길순' : '예: 신랑측, 신부측 / 상주 이름',
                helperText: _isFuneral
                    ? '여러 명이면 쉼표(,)로 나눠 적어 주세요'
                    : '쉼표(,)로 나눠 적어요. 비워 두면 구분 없이 받아요',
              ),
            ),
          ),
          if (_asksOperator) ...[
            const SizedBox(height: 20),
            TestId(
              'input_operator',
              child: TextField(
                controller: _operator,
                style: AppText.receptionName,
                decoration: const InputDecoration(
                  labelText: '받는 사람 이름',
                  hintText: '돈을 받는 분(내 이름)',
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const FieldLabel('식권'),
          _choiceRow([
            (
              '식권 기록 안 함',
              _mealEnabled == false,
              () => setState(() => _mealEnabled = false),
            ),
            (
              '식권도 기록',
              _mealEnabled == true,
              () => setState(() => _mealEnabled = true),
            ),
          ]),
          if (_mealEnabled == true) ...[
            const SizedBox(height: 12),
            const FieldLabel('기본 매수'),
            _choiceRow([
              for (final count in const [1, 2])
                (
                  '$count매',
                  _defaultMeals == count,
                  () => setState(() => _defaultMeals = count),
                ),
            ]),
          ],
          const SizedBox(height: 20),
          const FieldLabel('결제 방법'),
          _choiceRow([
            (
              '현금만',
              _methodEnabled == false,
              () => setState(() => _methodEnabled = false),
            ),
            (
              '계좌이체도 구분',
              _methodEnabled == true,
              () => setState(() => _methodEnabled = true),
            ),
          ]),
          const SizedBox(height: 28),
          TestId(
            'btn_start_reception',
            child: SizedBox(
              height: AppSpacing.receptionButton,
              child: FilledButton(
                onPressed:
                    _saving ||
                        (!_settingsOnly && _whose == null) ||
                        _mealEnabled == null ||
                        _methodEnabled == null
                    ? null
                    : (_isEdit ? _saveEdit : _start),
                style: FilledButton.styleFrom(
                  textStyle: AppText.receptionButton,
                ),
                child: Text(widget.editing || _isEdit ? '저장' : '받기 시작'),
              ),
            ),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 24),
            Center(
              child: TestId(
                'btn_event_delete',
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: _saving ? null : _delete,
                  child: const Text('행사 삭제'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 행사 수정의 구분 한 줄. [original]은 원래 있던 구분 이름(새로 추가한 줄은 null).
class _SideRow {
  _SideRow(this.original) : controller = TextEditingController(text: original);
  final String? original;
  final TextEditingController controller;
}
