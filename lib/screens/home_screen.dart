import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../services/format.dart';
import '../services/settings_service.dart';
import '../widgets/common.dart';
import 'event_detail_screen.dart';
import 'person_detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final year = DateTime.now().year;
    return Scaffold(
      appBar: AppBar(
        title: const Text('경조사 장부'),
        actions: [
          IconButton(
            iconSize: 30,
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: AsyncBody(
        value: home,
        builder: (data) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _BackupBanner(recordCount: data.recordCount),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text('$year년', style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                TotalTile(label: '올해 보낸 돈', amount: data.sent, color: sentColor),
                TotalTile(
                    label: '올해 받은 돈',
                    amount: data.received,
                    color: receivedColor),
              ]),
            ),
            const SectionTitle('다가오는 행사'),
            if (data.upcoming.isEmpty)
              const EmptyView(
                  icon: Icons.event_available,
                  message: '다가오는 행사가 없어요.\n장부 탭에서 행사를 등록해 보세요.')
            else
              for (final e in data.upcoming)
                ListTile(
                  leading: CircleAvatar(child: Text(e.type.characters.first)),
                  title: Text(e.title),
                  subtitle: Text(
                      '${formatDate(e.date)}${(e.place ?? '').isEmpty ? '' : ' · ${e.place}'}'),
                  trailing: Text(dDay(e.date),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary)),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => EventDetailScreen(eventId: e.id!))),
                ),
            const SectionTitle('최근 내역'),
            if (data.recent.isEmpty)
              const EmptyView(
                  icon: Icons.receipt_long,
                  message: '아직 기록이 없어요.\n사람 탭에서 사람을 추가하고 내역을 기록해 보세요.')
            else
              for (final r in data.recent)
                RecordTile(
                  record: r,
                  showPerson: true,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) =>
                              PersonDetailScreen(personId: r.personId))),
                ),
          ],
        ),
      ),
    );
  }
}

/// 기록 20개 이상인데 백업을 안 했거나 30일이 지나면 보이는 배너
class _BackupBanner extends ConsumerWidget {
  const _BackupBanner({required this.recordCount});
  final int recordCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = shouldShowBackupBanner(
      recordCount: recordCount,
      lastBackup: ref.watch(lastBackupProvider),
      dismissedAt: ref.watch(bannerDismissProvider),
    );
    if (!show) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: scheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.cloud_upload_outlined,
                  size: 32, color: scheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text('백업해 두면 폰을 바꿔도 기록이 안전해요',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: scheme.onPrimaryContainer)),
              ),
              IconButton(
                tooltip: '닫기',
                icon: const Icon(Icons.close),
                onPressed: () =>
                    ref.read(bannerDismissProvider.notifier).dismiss(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
