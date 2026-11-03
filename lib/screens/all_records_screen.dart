import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'person_detail_screen.dart';

/// 홈의 '전체 보기': 모든 내역 최신순
class AllRecordsScreen extends ConsumerWidget {
  const AllRecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('전체 기록')),
      body: AsyncBody(
        value: ref.watch(allRecordsProvider),
        builder: (records) => records.isEmpty
            ? const Center(
                child: EmptyView(icon: Icons.receipt_long, message: '아직 기록이 없어요.'))
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: records.length,
                separatorBuilder: (_, _) =>
                    const AppDivider(indent: AppSpacing.page),
                itemBuilder: (_, i) => RecordTile(
                  record: records[i],
                  showPerson: true,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => PersonDetailScreen(
                              personId: records[i].personId))),
                ),
              ),
      ),
    );
  }
}
