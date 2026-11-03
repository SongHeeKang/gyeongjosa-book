import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/person.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'person_form_sheet.dart';
import 'record_form_sheet.dart';

/// [기록하기] 버튼: 사람을 고르고(또는 새로 추가하고) 바로 내역 입력창을 연다.
Future<void> startQuickRecord(BuildContext context, WidgetRef ref) async {
  final picked = await showModalBottomSheet<_Pick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _PersonPickerSheet(),
  );
  if (picked == null || !context.mounted) return;

  int? personId = picked.personId;
  if (picked.addNew) {
    personId = await showPersonForm(context, ref);
  }
  if (personId == null || !context.mounted) return;
  await showRecordForm(context, personId: personId);
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
  const _PersonPickerSheet();

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
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 12),
              child: Text('누구와 주고받았나요?', style: AppText.appTitle),
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
