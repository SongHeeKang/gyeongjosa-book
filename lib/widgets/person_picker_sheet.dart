import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/person.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'person_form_sheet.dart';
import 'record_form_sheet.dart';

/// 사람을 고른다(또는 새로 추가). 고르지 않으면 null.
Future<int?> pickPerson(BuildContext context, WidgetRef ref,
    {required String title}) async {
  final picked = await showModalBottomSheet<_Pick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PersonPickerSheet(title: title),
  );
  if (picked == null || !context.mounted) return null;
  if (picked.addNew) return showPersonForm(context, ref);
  return picked.personId;
}

/// [보냈어요]: 사람을 고르고 바로 보낸 내역 입력창을 연다.
Future<void> startSentRecord(BuildContext context, WidgetRef ref) async {
  final personId = await pickPerson(context, ref, title: '누구에게 보냈나요?');
  if (personId == null || !context.mounted) return;
  await showRecordForm(context,
      personId: personId, initialDirection: Direction.sent);
}

class _Pick {
  final int? personId;
  final bool addNew;
  const _Pick.person(this.personId) : addNew = false;
  const _Pick.addNew()
      : personId = null,
        addNew = true;
}

class _PersonPickerSheet extends ConsumerStatefulWidget {
  const _PersonPickerSheet({required this.title});
  final String title;

  @override
  ConsumerState<_PersonPickerSheet> createState() => _PersonPickerSheetState();
}

class _PersonPickerSheetState extends ConsumerState<_PersonPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(allPeopleProvider).value ?? const <Person>[];
    final q = _search.text.trim();
    final list = q.isEmpty
        ? people
        : people.where((p) => p.name.contains(q)).toList();
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page, 0, AppSpacing.page, 12),
              child: Text(widget.title, style: AppText.appTitle),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '이름 검색',
                  prefixIcon: Icon(Icons.search, color: AppColors.icon),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.person_add_alt, color: AppColors.primary),
              title: Text('새 사람 추가',
                  style: AppText.listName.copyWith(color: AppColors.primary)),
              onTap: () => Navigator.pop(context, const _Pick.addNew()),
            ),
            const AppDivider(),
            Expanded(
              child: list.isEmpty
                  ? EmptyView(
                      icon: Icons.person_search,
                      message: people.isEmpty
                          ? '아직 등록한 사람이 없어요.\n[새 사람 추가]를 눌러 주세요.'
                          : '찾는 사람이 없어요.')
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(list[i].name),
                        subtitle: Text(list[i].relation),
                        onTap: () =>
                            Navigator.pop(context, _Pick.person(list[i].id)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
