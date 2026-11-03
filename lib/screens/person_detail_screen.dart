import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../services/format.dart';
import '../widgets/common.dart';
import '../widgets/person_form_sheet.dart';
import '../widgets/record_form_sheet.dart';

class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({super.key, required this.personId});
  final int personId;

  Future<void> _delete(BuildContext context, WidgetRef ref, String name) async {
    final ok = await confirmDialog(context,
        title: '사람 삭제',
        message: '$name 님과 주고받은 내역도 모두 삭제돼요.\n정말 삭제할까요?',
        okText: '삭제',
        destructive: true);
    if (!ok) return;
    await ref.read(repositoryProvider).deletePerson(personId);
    ref.refreshData();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(personDetailProvider(personId));
    return AsyncBody(
      value: detail,
      builder: (d) {
        if (d == null) {
          return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('삭제된 사람이에요.')));
        }
        final p = d.person;
        final diff = d.receivedTotal - d.sentTotal;
        return Scaffold(
          appBar: AppBar(
            title: Text(p.name),
            actions: [
              PopupMenuButton<String>(
                iconSize: 28,
                onSelected: (v) {
                  if (v == 'edit') showPersonForm(context, ref, existing: p);
                  if (v == 'delete') _delete(context, ref, p.name);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('정보 수정')),
                  PopupMenuItem(value: 'delete', child: Text('삭제')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
            onPressed: () => showRecordForm(context, personId: personId),
            icon: const Icon(Icons.add),
            label: const Text('내역 추가', style: TextStyle(fontSize: 18)),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  [
                    p.relation,
                    if ((p.phone ?? '').isNotEmpty) p.phone!,
                    if ((p.memo ?? '').isNotEmpty) p.memo!,
                  ].join(' · '),
                  style: const TextStyle(fontSize: 16, color: Colors.black54),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  TotalTile(label: '보낸 돈', amount: d.sentTotal, color: sentColor),
                  TotalTile(
                      label: '받은 돈', amount: d.receivedTotal, color: receivedColor),
                ]),
              ),
              _DiffCard(diff: diff),
              SectionTitle('내역 ${d.records.length}건'),
              if (d.records.isEmpty)
                const EmptyView(
                    icon: Icons.receipt_long,
                    message: '아직 기록이 없어요.\n[내역 추가]를 눌러 기록해 보세요.')
              else
                for (final r in d.records)
                  RecordTile(
                    record: r,
                    onTap: () =>
                        showRecordForm(context, personId: personId, existing: r),
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// 차액: 받은 만큼 돌려줄 금액 감 잡기
class _DiffCard extends StatelessWidget {
  const _DiffCard({required this.diff});
  final int diff;

  @override
  Widget build(BuildContext context) {
    final String text;
    final Color color;
    if (diff > 0) {
      text = '받은 돈이 ${formatWon(diff)} 더 많아요.\n다음 경조사 때 참고하세요.';
      color = receivedColor;
    } else if (diff < 0) {
      text = '보낸 돈이 ${formatWon(-diff)} 더 많아요.';
      color = sentColor;
    } else {
      text = '주고받은 금액이 같아요.';
      color = Colors.black54;
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.balance, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
