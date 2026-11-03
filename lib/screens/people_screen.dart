import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/person.dart';
import '../services/format.dart';
import '../services/limits.dart';
import '../services/pro_service.dart';
import '../widgets/common.dart';
import '../widgets/person_form_sheet.dart';
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
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${people.value?.length ?? 0} / ${FreeLimits.people}명',
                  style: const TextStyle(fontSize: 16, color: Colors.black54),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _add,
        icon: const Icon(Icons.person_add),
        label: const Text('사람 추가', style: TextStyle(fontSize: 18)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '이름, 전화번호, 메모 검색',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final r in [null, ...Relations.all])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(r ?? '전체'),
                      selected: _relation == r,
                      onSelected: (_) => setState(() => _relation = r),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncBody(
              value: people,
              builder: (all) {
                final list = _filter(all);
                if (all.isEmpty) {
                  return const Center(
                      child: EmptyView(
                          icon: Icons.people_outline,
                          message: '아직 등록한 사람이 없어요.\n아래 [사람 추가]를 눌러 보세요.'));
                }
                if (list.isEmpty) {
                  return const Center(
                      child: EmptyView(
                          icon: Icons.search_off, message: '찾는 사람이 없어요.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _PersonRow(summary: list[i]),
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
    return ListTile(
      onTap: () => Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => PersonDetailScreen(personId: p.id!))),
      leading: CircleAvatar(
        radius: 24,
        child: Text(p.name.characters.first, style: const TextStyle(fontSize: 20)),
      ),
      title: Row(
        children: [
          Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Text(p.relation,
              style: const TextStyle(fontSize: 15, color: Colors.black54)),
        ],
      ),
      subtitle: Text.rich(TextSpan(children: [
        TextSpan(
            text: '보냄 ${formatWon(summary.sentTotal)}',
            style: const TextStyle(color: sentColor)),
        const TextSpan(text: '  /  '),
        TextSpan(
            text: '받음 ${formatWon(summary.receivedTotal)}',
            style: const TextStyle(color: receivedColor)),
      ])),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
