import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../services/format.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/amount_input.dart';
import '../widgets/common.dart';
import '../widgets/pro_gate.dart';

/// 행사 등록/수정
class EventFormScreen extends ConsumerStatefulWidget {
  const EventFormScreen({super.key, this.existing, this.initialIsMine = false});
  final Event? existing;
  final bool initialIsMine;

  @override
  ConsumerState<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends ConsumerState<EventFormScreen> {
  final _title = TextEditingController();
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
  }

  @override
  void dispose() {
    _title.dispose();
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

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showSnack(context, '행사 이름을 입력해 주세요. 예: 철수 결혼식');
      return;
    }
    // 내 행사 장부는 무료 1개. (기존 내 행사를 수정하는 건 항상 가능)
    final becomesMine = _isMine && widget.existing?.isMine != true;
    if (becomesMine && !await ensureCanAddMyEvent(context, ref)) return;
    if (!mounted) return;

    setState(() => _saving = true);
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? '행사 추가' : '행사 수정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, 8, AppSpacing.page, 32),
        children: [
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
          const FieldLabel('종류'),
          ChoiceChips(
            options: EventTypes.all,
            selected: _type,
            onSelected: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              labelText: '행사 이름',
              hintText: _isMine ? '예: 우리 결혼식' : '예: 김철수 결혼식',
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
            controller: _place,
            decoration: const InputDecoration(labelText: '장소 (선택)'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _memo,
            decoration: const InputDecoration(labelText: '메모 (선택)'),
          ),
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
            onPressed: _saving ? null : _save,
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
}
