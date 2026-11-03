import 'package:flutter/material.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/person.dart';
import '../theme/app_theme.dart';
import 'amount_input.dart';
import 'common.dart';
import 'pro_gate.dart';

/// 사람 추가/수정 창. 새로 추가하면 새 사람의 id, 수정이면 기존 id 를 돌려준다.
/// 새로 추가할 때는 무료 한도(30명)를 먼저 확인한다.
Future<int?> showPersonForm(BuildContext context, WidgetRef ref,
    {Person? existing}) async {
  if (existing == null && !await ensureCanAddPerson(context, ref)) return null;
  if (!context.mounted) return null;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => PersonFormSheet(existing: existing),
  );
}

class PersonFormSheet extends ConsumerStatefulWidget {
  const PersonFormSheet({super.key, this.existing});
  final Person? existing;

  @override
  ConsumerState<PersonFormSheet> createState() => _PersonFormSheetState();
}

class _PersonFormSheetState extends ConsumerState<PersonFormSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _memo = TextEditingController();
  late String _relation;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name.text = e?.name ?? '';
    _phone.text = e?.phone ?? '';
    _memo.text = e?.memo ?? '';
    _relation = e?.relation ?? '지인';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _memo.dispose();
    super.dispose();
  }

  /// 시스템 연락처 선택창 사용 → 연락처 읽기 권한이 필요 없다.
  Future<void> _pickContact() async {
    try {
      final contact = await FlutterNativeContactPicker().selectPhoneNumber();
      if (contact == null) return;
      setState(() {
        _name.text = contact.fullName ?? _name.text;
        final phone = contact.selectedPhoneNumber ??
            (contact.phoneNumbers?.isNotEmpty == true
                ? contact.phoneNumbers!.first
                : null);
        if (phone != null) _phone.text = phone;
      });
    } catch (e) {
      if (mounted) showSnack(context, '연락처를 불러오지 못했어요.');
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, '이름을 입력해 주세요.');
      return;
    }
    final repo = ref.read(repositoryProvider);
    final phone = _phone.text.trim().isEmpty ? null : _phone.text.trim();
    final memo = _memo.text.trim().isEmpty ? null : _memo.text.trim();
    int id;
    if (widget.existing == null) {
      id = await repo.insertPerson(Person(
        name: name,
        relation: _relation,
        phone: phone,
        memo: memo,
        createdAt: DateTime.now(),
      ));
    } else {
      final e = widget.existing!;
      await repo.updatePerson(Person(
        id: e.id,
        name: name,
        relation: _relation,
        phone: phone,
        memo: memo,
        createdAt: e.createdAt,
      ));
      id = e.id!;
    }
    ref.refreshData();
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.page, 0, AppSpacing.page, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? '사람 추가' : '정보 수정',
                style: AppText.appTitle),
            const SizedBox(height: 16),
            if (widget.existing == null) ...[
              OutlinedButton.icon(
                onPressed: _pickContact,
                icon: const Icon(Icons.contacts),
                label: const Text('연락처에서 가져오기'),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(labelText: '이름'),
            ),
            const SizedBox(height: 16),
            const FieldLabel('관계'),
            ChoiceChips(
              options: Relations.all,
              selected: _relation,
              onSelected: (v) => setState(() => _relation = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: '전화번호 (선택)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _memo,
              decoration: const InputDecoration(labelText: '메모 (선택)'),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('저장')),
          ],
        ),
      ),
    );
  }
}
