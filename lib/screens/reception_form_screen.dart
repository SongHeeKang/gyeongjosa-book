import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/amount_input.dart';
import '../widgets/common.dart';
import 'reception_screen.dart';

/// 접수 시작: 행사 이름, 종류, 날짜, 구분, 접수자
class ReceptionFormScreen extends ConsumerStatefulWidget {
  const ReceptionFormScreen({super.key});

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

  bool get _isFuneral => _type == '장례';

  static String _defaultSidesFor(String type) =>
      type == '결혼' ? ReceptionDefaults.weddingSides.join(', ') : '';

  @override
  void initState() {
    super.initState();
    _sides.text = _defaultSidesFor(_type);
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
      // 직접 고쳐 쓴 구분은 그대로 두고, 기본값일 때만 종류에 맞춰 바꾼다.
      if (_sides.text.trim() == _defaultSidesFor(_type)) {
        _sides.text = _defaultSidesFor(type);
      }
      _type = type;
    });
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

  Future<void> _start() async {
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
      showSnack(context, '접수자 이름을 입력해 주세요.');
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
            builder: (_) => ReceptionScreen(receptionId: reception.id)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('접수 시작')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 32),
        children: [
          const FieldLabel('종류'),
          ChoiceChips(
            options: EventTypes.all,
            selected: _type,
            onSelected: _selectType,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _title,
            style: AppText.receptionName,
            decoration: const InputDecoration(
              labelText: '행사 이름',
              hintText: '예: 홍길동 · 김영희 결혼식',
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today),
            label: Text(formatDate(_date)),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _sides,
            style: AppText.receptionName,
            decoration: InputDecoration(
              labelText: _isFuneral ? '상주 이름' : '구분',
              hintText: _isFuneral ? '예: 홍길동, 홍길순' : '예: 신랑측, 신부측',
              helperText: _isFuneral
                  ? '여러 명이면 쉼표(,)로 나눠 적어 주세요'
                  : '쉼표(,)로 나눠 적어요. 비워 두면 구분 없이 받아요',
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _operator,
            style: AppText.receptionName,
            decoration: const InputDecoration(
              labelText: '접수자 이름',
              hintText: '접수를 맡은 분 이름',
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: AppSpacing.receptionButton,
            child: FilledButton(
              onPressed: _saving ? null : _start,
              style: FilledButton.styleFrom(
                  textStyle: AppText.receptionButton),
              child: const Text('접수 시작'),
            ),
          ),
        ],
      ),
    );
  }
}
