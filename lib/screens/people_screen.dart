import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/person.dart';
import '../services/format.dart';
import '../services/limits.dart';
import '../services/pro_service.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/common.dart';
import '../widgets/person_form_sheet.dart';
import '../widgets/coach_mark.dart';
import '../widgets/screen_coach.dart';
import '../widgets/settings_button.dart';
import 'person_detail_screen.dart';

class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final _search = TextEditingController();
  String? _relation; // null = 전체

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<PersonSummary> _filter(List<PersonSummary> all) {
    final q = _search.text.trim();
    return all.where((s) {
      if (_relation != null && s.person.relation != _relation) return false;
      if (q.isEmpty) return true;
      return s.person.name.contains(q) ||
          (s.person.phone ?? '').replaceAll('-', '').contains(q.replaceAll('-', '')) ||
          (s.person.memo ?? '').contains(q);
    }).toList();
  }

  Future<void> _add() async {
    final id = await showPersonForm(context, ref);
    if (id != null && mounted) {
      await Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => PersonDetailScreen(personId: id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(peopleSummariesProvider);
    final isPro = ref.watch(isProProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('사람'),
        actions: [
          if (!isPro)
            Center(
              child: Text(
                '${people.value?.length ?? 0} / ${FreeLimits.people}명',
                style: AppText.sub,
              ),
            ),
          TestId('btn_add_person', child: TextButton(onPressed: _add, child: const Text('사람 추가'))),
          const HelpButton(screen: CoachScreen.people),
          const SettingsButton(),
          SettingsButton.trailingGap,
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.page, 4, AppSpacing.page, 4),
            child: CoachTarget(
              spot: CoachSpot.peopleSearch,
              child: TestId('people_search', child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '이름, 전화번호, 메모 검색',
                prefixIcon: const Icon(Icons.search, color: AppColors.icon),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            )),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              children: [
                for (final r in [null, ...Relations.all])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TestId('people_filter_${r ?? '전체'}', child: ChoiceChip(
                      showCheckmark: false,
                      label: Text(r ?? '전체'),
                      selected: _relation == r,
                      onSelected: (_) => setState(() => _relation = r),
                    )),
                  ),
              ],
            ),
          ),
          const AppDivider(),
          Expanded(
            child: AsyncBody(
              value: people,
              builder: (all) {
                final list = _filter(all);
                if (all.isEmpty) {
                  return const Center(
                      child: EmptyView(
                          icon: Icons.people_outline,
                          message: '축의금 · 부의금을 주고받은 사람이\n여기에 모여요'));
                }
                if (list.isEmpty) {
                  return const Center(
                      child: EmptyView(
                          icon: Icons.search_off, message: '찾는 사람이 없어요.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const AppDivider(indent: AppSpacing.page),
                  itemBuilder: (_, i) => i == 0
                      ? CoachTarget(
                          spot: CoachSpot.peopleCard,
                          child: _PersonRow(summary: list[i]))
                      : _PersonRow(summary: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.summary});
  final PersonSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = summary.person;
    return TestId('people_item_${p.name}', child: InkWell(
      onTap: () => Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => PersonDetailScreen(personId: p.id!))),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page, vertical: AppSpacing.item + 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                        child: Text(p.name,
                            style: AppText.listName,
                            overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    Text(p.relation, style: AppText.sub),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '보냄 ${formatWon(summary.sentTotal)} · 받음 ${formatWon(summary.receivedTotal)}',
                    style: AppText.sub,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.divider),
          ],
        ),
      ),
    ));
  }
}
