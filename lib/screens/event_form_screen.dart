import '../widgets/unsaved_guard.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../models/person.dart';
import '../services/format.dart';
import '../services/limit_service.dart';
import '../services/notification_permission.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/amount_input.dart';
import '../widgets/common.dart';
import '../widgets/person_name_field.dart';

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

  /// 처음 열었을 때의 값. 뒤로 갈 때 달라졌으면 작성 중 확인을 묻는다.
  late final String _initial;
  String get _snapshot => [
    _title.text,
    _name.text,
    _place.text,
    _memo.text,
    _type,
    _date,
    _isMine,
    _notify,
    _relation,
    _selected?.id,
  ].join('|');

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? EventTypes.all.first;
    _date = e?.date ?? DateTime.now();
    _isMine = e?.isMine ?? widget.initialIsMine;
    _notify = e?.notify ?? true; // 전날 알림 기본 켜짐
    // 휴대폰 설정에서 바꿨을 수 있으니 열 때마다 다시 확인한다
    Future.microtask(
      () => ref.read(notificationPermissionProvider.notifier).refresh(),
    );
    _title.text = e?.title ?? '';
    _place.text = e?.place ?? '';
    _memo.text = e?.memo ?? '';
    _initial = _snapshot;
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

  void _onNotifyChanged(bool value) => setState(() => _notify = value);

  /// 알림 권한이 없으면 전날 알림을 쓸 수 없다. 권한을 받으면 스위치가 켜진다.
  Future<void> _askPermission() async {
    if (await askNotificationPermission(context, ref) && mounted) {
      setState(() => _notify = true);
    }
  }

  /// 일정의 사람을 찾거나 새로 등록한다. 한도에 막히면 null.
  Future<int?> _resolvePerson(String name) async {
    final repo = ref.read(repositoryProvider);
    if (_selected != null) return _selected!.id;
    final same = await repo.findPeopleByExactName(name);
    if (same.isNotEmpty) return same.first.id;
    if (!mounted || !await LimitService.canAddNewPerson(context, ref)) {
      return null;
    }
    return repo.insertPerson(
      Person(name: name, relation: _relation, createdAt: DateTime.now()),
    );
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
    final title = isSchedule
        ? Event.scheduleTitle(name, _type)
        : _title.text.trim();
    if (isSchedule && name.isEmpty) {
      showSnack(context, '이름을 입력해 주세요.');
      return;
    }
    if (title.isEmpty) {
      showSnack(context, '행사 이름을 입력해 주세요. 예: 철수 결혼식');
      return;
    }
    final personId = isSchedule
        ? await _resolvePerson(name)
        : widget.existing?.personId;
    if (isSchedule && personId == null) return;
    if (!mounted) return;
    // 내 행사 장부는 무료 1개. (기존 내 행사를 수정하는 건 항상 가능)
    final becomesMine = _isMine && widget.existing?.isMine != true;
    if (becomesMine && !await LimitService.canCreateMyEvent(context, ref)) {
      return;
    }
    if (!mounted) return;

    final repo = ref.read(repositoryProvider);
    var event = Event(
      id: widget.existing?.id,
      type: _type,
      title: title,
      date: _date,
      isMine: _isMine,
      place: _place.text.trim().isEmpty ? null : _place.text.trim(),
      memo: _memo.text.trim().isEmpty ? null : _memo.text.trim(),
      // 알림 권한이 없으면 전날 알림은 꺼진 채로 저장한다
      notify: _notify && ref.read(notificationPermissionProvider),
      personId: personId,
      pendingHidden: widget.existing?.pendingHidden ?? false,
    );
    if (becomesMine) {
      // 저장 순간 안전장치: 한도를 넘으면 저장하지 않고 결제 화면
      final toSave = event;
      final saved = await LimitService.saveMyEvent(context, ref, (max) async {
        if (widget.existing == null) {
          return repo.insertEvent(toSave, maxMyEvents: max);
        }
        await repo.updateEvent(toSave, maxMyEvents: max);
        return toSave.id!;
      });
      if (saved == null) return;
      event = (await repo.getEvent(saved))!;
    } else if (widget.existing == null) {
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
  Widget build(BuildContext context) => UnsavedChangesGuard(
    isDirty: () => _snapshot != _initial,
    child: _buildForm(context),
  );

  Widget _buildForm(BuildContext context) {
    final reminder = NotificationService.reminderTime(_date);
    final reminderPast = !reminder.isAfter(DateTime.now());
    final notifAllowed = ref.watch(notificationPermissionProvider);
    final isSchedule = widget.isSchedule;
    final people = ref.watch(allPeopleProvider).value ?? const <Person>[];
    final hasName = _name.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing != null
              ? '행사 수정'
              : (isSchedule ? '일정 추가' : '내 행사 만들기'),
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
            TestId(
              'input_name',
              child: PersonNameField(
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
            ),
            const SizedBox(height: 20),
            if (_selected == null) ...[
              const FieldLabel('관계'),
              ChoiceChips(
                testIdPrefix: 'select_relation',
                options: Relations.all,
                selected: _relation,
                onSelected: (v) => setState(() => _relation = v),
              ),
              const SizedBox(height: 20),
            ],
          ],
          const FieldLabel('종류'),
          ChoiceChips(
            testIdPrefix: 'select_event_type',
            options: EventTypes.all,
            selected: _type,
            onSelected: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 20),
          if (!isSchedule) ...[
            TestId(
              'input_event_title',
              child: TextField(
                controller: _title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  labelText: '행사 이름',
                  hintText: _isMine ? '예: 우리 결혼식' : '예: 김철수 결혼식',
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          TestId(
            'input_date',
            child: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(formatDate(_date)),
            ),
          ),
          const SizedBox(height: 20),
          TestId(
            'input_place',
            child: TextField(
              controller: _place,
              decoration: const InputDecoration(labelText: '장소 (선택)'),
            ),
          ),
          if (!isSchedule) ...[
            const SizedBox(height: 16),
            TestId(
              'input_memo',
              child: TextField(
                controller: _memo,
                decoration: const InputDecoration(labelText: '메모 (선택)'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // 알림 권한이 없으면 스위치를 막고 권한부터 받게 한다
          TestId(
            'switch_notify',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('전날 오전 9시 알림', style: AppText.listName),
              subtitle: Text(
                !notifAllowed
                    ? '알림 권한이 없어 쓸 수 없어요'
                    : reminderPast
                    ? '이미 지난 날짜라 알림이 울리지 않아요'
                    : '${formatShortDate(reminder)} 오전 9시쯤 알려드려요',
              ),
              value: notifAllowed && _notify,
              onChanged: notifAllowed ? _onNotifyChanged : null,
            ),
          ),
          if (!notifAllowed)
            Align(
              alignment: Alignment.centerLeft,
              child: TestId(
                'btn_allow_notify',
                child: OutlinedButton.icon(
                  onPressed: _askPermission,
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('알림 허용하기'),
                ),
              ),
            ),
          const SizedBox(height: 20),
          TestId(
            'btn_save',
            child: FilledButton(
              onPressed: _saving ? null : _onSavePressed,
              child: const Text('저장'),
            ),
          ),
        ],
      ),
    );
  }
}
