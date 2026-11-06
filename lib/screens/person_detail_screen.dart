import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
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
        final info = [
          p.relation,
          if ((p.phone ?? '').isNotEmpty) p.phone!,
          if ((p.memo ?? '').isNotEmpty) p.memo!,
        ].join(' · ');
        return Scaffold(
          appBar: AppBar(
            title: Text(p.name),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.icon),
                onSelected: (v) {
                  if (v == 'edit') showPersonForm(context, ref, existing: p);
                  if (v == 'delete') _delete(context, ref, p.name);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('정보 수정')),
                  PopupMenuItem(value: 'delete', child: Text('삭제')),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          floatingActionButtonLocation: const RecordFabLocation(),
          floatingActionButton: RecordFab(
            onPressed: () => showRecordForm(context, personId: personId),
          ),
          body: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, 0, AppSpacing.page, 16),
                child: Text(info, style: AppText.sub),
              ),
              SummaryRow(sent: d.sentTotal, received: d.receivedTotal),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, 16, AppSpacing.page, 0),
                child: Text(
                  diff > 0
                      ? '받은 돈이 ${formatWon(diff)} 더 많아요. 다음 경조사 때 참고하세요.'
                      : diff < 0
                          ? '보낸 돈이 ${formatWon(-diff)} 더 많아요.'
                          : '주고받은 금액이 같아요.',
                  style: AppText.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: diff > 0 ? AppColors.primary : AppColors.textSub),
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              const AppDivider(),
              SectionTitle('내역 ${d.records.length}건'),
              if (d.records.isEmpty)
                const EmptyView(
                    icon: Icons.receipt_long,
                    message: '아직 기록이 없어요.\n오른쪽 아래 연필 버튼을 눌러 기록해 보세요.')
              else
                for (final r in d.records)
                  RecordTile(
                    record: r,
                    onTap: () =>
                        showRecordForm(context, personId: personId, existing: r),
                  ),
              fabBottomSpace,
            ],
          ),
        );
      },
    );
  }
}
