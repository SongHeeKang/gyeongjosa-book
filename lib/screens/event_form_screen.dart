import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../models/person.dart';
import '../services/format.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/amount_input.dart';
import '../widgets/common.dart';
import '../widgets/person_name_field.dart';
import '../widgets/pro_gate.dart';

/// 행사 수정, 내 행사 만들기, 일정 추가(남의 행사).
/// 일정 추가는 이름 · 종류 · 날짜 · 장소 · 전날 알림만 받고, 금액은 다녀온 뒤에 적는다.
class EventFormScreen extends ConsumerStatefulWidget {
  const EventFormScreen({super.key, this.existing, this.initialIsMine = false});
  final Event? existing;
  final bool initialIsMine;

  bool get isSchedule => existing == null && !initialIsMine;

  @override
  ConsumerState<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends ConsumerState<EventFormScreen> {
  final _title = TextEditingController();
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  Person? _selected; // 자동완성에서 고른 기존 사람
  String _relation = '지인';
  final _place = TextEditingController();
  final _memo = TextEditingController();
  late String _type;
  late DateTime _date;
  late bool _isMine;
  late bool _notify;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? EventTypes.all.first;
    _date = e?.date ?? DateTime.now();
    _isMine = e?.isMine ?? widget.initialIsMine;
    _notify = e?.notify ?? true; // 전날 알림 기본 켜짐
    _title.text = e?.title ?? '';
    _place.text = e?.place ?? '';
    _memo.text = e?.memo ?? '';
    _name.addListener(() {
      // 고른 뒤 이름을 고치면 연결 해제
      if (_selected != null && _name.text.trim() != _selected!.name) {
        setState(() => _selected = null);
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _name.dispose();
    _nameFocus.dispose();
    _place.dispose();
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

  Future<void> _onNotifyChanged(bool value) async {
    setState(() => _notify = value);
    if (value) {
      await NotificationService.instance
          .ensurePermission(context, ref.read(prefsProvider));
    }
  }

  /// 일정의 사람을 찾거나 새로 등록한다. 한도에 막히면 null.
  Future<int?> _resolvePerson(String name) async {
    final repo = ref.read(repositoryProvider);
    if (_selected != null) return _selected!.id;
    final same = await repo.findPeopleByExactName(name);
    if (same.isNotEmpty) return same.first.id;
    if (!mounted || !await ensureCanAddPerson(context, ref)) return null;
    return repo.insertPerson(
        Person(name: name, relation: _relation, createdAt: DateTime.now()));
  }

  /// 두 번 눌러도 한 번만 저장되도록 끝날 때까지 버튼을 막는다.
  Future<void> _onSavePressed() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _save();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final isSchedule = widget.isSchedule;
    final name = _name.text.trim();
    final title =
        isSchedule ? Event.scheduleTitle(name, _type) : _title.text.trim();
    if (isSchedule && name.isEmpty) {
      showSnack(context, '이름을 입력해 주세요.');
      return;
    }
    if (title.isEmpty) {
      showSnack(context, '행사 이름을 입력해 주세요. 예: 철수 결혼식');
      return;
    }
    final personId =
        isSchedule ? await _resolvePerson(name) : widget.existing?.personId;
    if (isSchedule && personId == null) return;
    if (!mounted) return;
    // 내 행사 장부는 무료 1개. (기존 내 행사를 수정하는 건 항상 가능)
    final becomesMine = _isMine && widget.existing?.isMine != true;
    if (becomesMine && !await ensureCanAddMyEvent(context, ref)) return;
    if (!mounted) return;

    // 처음 알림을 켤 때 한 번만 이유를 설명하고 권한 요청 (스위치를 다시 켜면 또 물어봄)
    final prefs = ref.read(prefsProvider);
    if (_notify && prefs.getBool(PrefKeys.notifPermissionAsked) != true) {
      await NotificationService.instance.ensurePermission(context, prefs);
    }
    final repo = ref.read(repositoryProvider);
    var event = Event(
      id: widget.existing?.id,
      type: _type,
      title: title,
      date: _date,
      isMine: _isMine,
      place: _place.text.trim().isEmpty ? null : _place.text.trim(),
      memo: _memo.text.trim().isEmpty ? null : _memo.text.trim(),
      notify: _notify,
      personId: personId,
      pendingHidden: widget.existing?.pendingHidden ?? false,
    );
    if (widget.existing == null) {
      final id = await repo.insertEvent(event);
      event = (await repo.getEvent(id))!;
    } else {
      await repo.updateEvent(event);
    }
    await NotificationService.instance.scheduleForEvent(event);
    ref.refreshData();
    if (mounted) Navigator.pop(context, event.id);
  }

  @override
  Widget build(BuildContext context) {
    final reminder = NotificationService.reminderTime(_date);
    final reminderPast = !reminder.isAfter(DateTime.now());
    final isSchedule = widget.isSchedule;
    final people = ref.watch(allPeopleProvider).value ?? const <Person>[];
    final hasName = _name.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.existing != null
              ? '행사 수정'
              : (isSchedule ? '일정 추가' : '내 행사 만들기'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, 8, AppSpacing.page, 32),
        children: [
          if (widget.existing != null) ...[
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('남의 행사 (내가 감)')),
                ButtonSegment(value: true, label: Text('내 행사 (내가 받음)')),
              ],
              selected: {_isMine},
              onSelectionChanged: (s) => setState(() => _isMine = s.first),
            ),
            const SizedBox(height: 20),
          ],
          if (isSchedule) ...[
            PersonNameField(
              controller: _name,
              focusNode: _nameFocus,
              people: people,
              hintText: '예: 김철수',
              helperText: _selected != null
                  ? '기존 사람(${_selected!.relation})에 연결돼요'
                  : (hasName ? '처음 보는 이름이면 새로 등록돼요' : null),
              onSelected: (p) => setState(() => _selected = p),
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 20),
            if (_selected == null) ...[
              const FieldLabel('관계'),
              ChoiceChips(
                options: Relations.all,
                selected: _relation,
                onSelected: (v) => setState(() => _relation = v),
              ),
              const SizedBox(height: 20),
            ],
          ],
          const FieldLabel('종류'),
          ChoiceChips(
            options: EventTypes.all,
            selected: _type,
            onSelected: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 20),
          if (!isSchedule) ...[
            TextField(
              controller: _title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                labelText: '행사 이름',
                hintText: _isMine ? '예: 우리 결혼식' : '예: 김철수 결혼식',
              ),
            ),
            const SizedBox(height: 20),
          ],
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today),
            label: Text(formatDate(_date)),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _place,
            decoration: const InputDecoration(labelText: '장소 (선택)'),
          ),
          if (!isSchedule) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _memo,
              decoration: const InputDecoration(labelText: '메모 (선택)'),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('전날 오전 9시 알림', style: AppText.listName),
            subtitle: Text(reminderPast
                ? '이미 지난 날짜라 알림이 울리지 않아요'
                : '${formatShortDate(reminder)} 오전 9시쯤 알려드려요'),
            value: _notify,
            onChanged: _onNotifyChanged,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _onSavePressed,
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
}
