import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/amount_input.dart';
import '../widgets/common.dart';
import '../services/receive_targets.dart';
import 'receive_money_screen.dart';

/// 행사 설정.
/// - 다른 사람 행사(대신 받기): 행사 이름, 종류, 날짜, 구분, 받는 사람, 식권, 결제 방법
///   → [받기 시작]을 누르면 receptions에 저장하고 받은 돈 적기 화면으로 간다.
/// - 내 행사([ReceptionFormScreen.myEvent]): 구분, 식권, 결제 방법만. 행사마다 처음 한 번
///   묻고, 받은 돈 적기 화면의 현황 줄에서 다시 바꿀 수 있다([editing]).
class ReceptionFormScreen extends ConsumerStatefulWidget {
  const ReceptionFormScreen({super.key})
      : event = null,
        editing = false;

  const ReceptionFormScreen.myEvent(
      {super.key, required Event this.event, this.editing = false});

  /// 내 행사의 받기 설정이면 그 행사
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

  bool get _isFuneral => _type == '장례';
  bool get _isWedding => _type == '결혼';
  bool get _isMine => widget.event != null;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _title.dispose();
    _sides.dispose();
    _operator.dispose();
    super.dispose();
  }

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
    setState(() => _sides.text = [
          ...presets.where(picked.contains),
          ...picked.where((s) => !presets.contains(s)),
        ].join(', '));
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
  };

  Widget _choiceRow(List<(String, bool, VoidCallback)> choices) {
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
                  backgroundColor: choices[i].$2 ? AppColors.primarySoft : null,
                  foregroundColor: choices[i].$2 ? AppColors.primary : null,
                  side: choices[i].$2
                      ? const BorderSide(color: AppColors.primary, width: 1.5)
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
    await ref.read(repositoryProvider).updateEventReceiveSettings(
        event.withReceiveSettings(
          sides: sides.isEmpty ? const [ReceptionDefaults.noSide] : sides,
          mealTicketEnabled: _mealEnabled!,
          defaultMealTickets: _defaultMeals,
          methodEnabled: _methodEnabled!,
        ));
    ref.refreshData();
    if (!mounted) return;
    if (widget.editing) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
            builder: (_) =>
                ReceiveMoneyScreen(target: MyEventTarget(event.id!))));
  }

  Future<void> _start() async {
    if (widget.event case final event?) return _saveMyEvent(event);
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
                ReceiveMoneyScreen(target: ReceptionTarget(reception.id))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('행사 설정')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 32),
        children: [
          if (_isMine) ...[
            Text('내 행사 · ${widget.event!.title}', style: AppText.sectionTitle),
            const SizedBox(height: 4),
            const Text('이 행사에서 받을 때 쓸 설정이에요. 받는 중에도 바꿀 수 있어요.',
                style: AppText.sub),
            const SizedBox(height: 20),
          ] else ...[
          const FieldLabel('종류'),
          ChoiceChips(
            testIdPrefix: 'select_event_type',
            options: EventTypes.all,
            selected: _type,
            onSelected: _selectType,
          ),
          const SizedBox(height: 20),
          TestId('input_event_title', child: TextField(
            controller: _title,
            style: AppText.receptionName,
            decoration: const InputDecoration(
              labelText: '행사 이름',
              hintText: '예: 홍길동 · 김영희 결혼식',
            ),
          )),
          const SizedBox(height: 20),
          TestId('input_date', child: OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today),
            label: Text(formatDate(_date)),
          )),
          const SizedBox(height: 20),
          ],
          if (_isWedding) ...[
            const FieldLabel('구분'),
            _weddingSideButtons(),
            const SizedBox(height: 12),
          ],
          TestId('input_side', child: TextField(
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
              hintText:
                  _isFuneral ? '예: 홍길동, 홍길순' : '예: 신랑측, 신부측 / 상주 이름',
              helperText: _isFuneral
                  ? '여러 명이면 쉼표(,)로 나눠 적어 주세요'
                  : '쉼표(,)로 나눠 적어요. 비워 두면 구분 없이 받아요',
            ),
          )),
          if (!_isMine) ...[
            const SizedBox(height: 20),
            TestId('input_operator', child: TextField(
              controller: _operator,
              style: AppText.receptionName,
              decoration: const InputDecoration(
                labelText: '받는 사람 이름',
                hintText: '돈을 받는 분(내 이름)',
              ),
            )),
          ],
          const SizedBox(height: 20),
          const FieldLabel('식권'),
          _choiceRow([
            ('식권 기록 안 함', _mealEnabled == false,
                () => setState(() => _mealEnabled = false)),
            ('식권도 기록', _mealEnabled == true,
                () => setState(() => _mealEnabled = true)),
          ]),
          if (_mealEnabled == true) ...[
            const SizedBox(height: 12),
            const FieldLabel('기본 매수'),
            _choiceRow([
              for (final count in const [1, 2])
                ('$count매', _defaultMeals == count,
                    () => setState(() => _defaultMeals = count)),
            ]),
          ],
          const SizedBox(height: 20),
          const FieldLabel('결제 방법'),
          _choiceRow([
            ('현금만', _methodEnabled == false,
                () => setState(() => _methodEnabled = false)),
            ('계좌이체도 구분', _methodEnabled == true,
                () => setState(() => _methodEnabled = true)),
          ]),
          const SizedBox(height: 28),
          TestId('btn_start_reception', child: SizedBox(
            height: AppSpacing.receptionButton,
            child: FilledButton(
              onPressed: _saving || _mealEnabled == null || _methodEnabled == null
                  ? null
                  : _start,
              style: FilledButton.styleFrom(
                  textStyle: AppText.receptionButton),
              child: Text(widget.editing ? '저장' : '받기 시작'),
            ),
          )),
        ],
      ),
    );
  }
}
