import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database_helper.dart';
import '../screens/settings_screen.dart';
import '../services/auto_backup_service.dart';
import '../services/backup_service.dart';
import '../services/format.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'test_id.dart';

/// 마지막 백업(자동 · 수동 중 늦은 것). 백업하면 바로 바뀐다.
final latestBackupProvider = Provider<DateTime?>((ref) {
  final manual = ref.watch(lastBackupProvider);
  final auto = ref.watch(autoBackupProvider).lastAt;
  if (manual == null) return auto;
  if (auto == null) return manual;
  return manual.isAfter(auto) ? manual : auto;
});

/// 홈 백업 아이콘 상태
enum BackupStatus {
  /// 7일 이내에 백업함: 초록 체크
  ok,

  /// 그 사이: 회색
  normal,

  /// 기록이 1건 이상인데 백업이 없거나 30일이 지남: 주황 점
  due,
}

BackupStatus backupStatus({
  required int recordCount,
  required DateTime? lastBackup,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  if (lastBackup != null &&
      today.difference(lastBackup) <= const Duration(days: 7)) {
    return BackupStatus.ok;
  }
  if (recordCount > 0 &&
      (lastBackup == null ||
          today.difference(lastBackup) > const Duration(days: 30))) {
    return BackupStatus.due;
  }
  return BackupStatus.normal;
}

/// '2026.11.20 오후 3:12'
String formatBackupTime(DateTime d) => '${formatDotDate(d)} ${formatTime(d)}';

/// 홈 요약 카드 제목 줄 오른쪽: 구름 아이콘 + 작은 글자 '백업' (누르는 영역 48dp)
class BackupStatusButton extends ConsumerWidget {
  const BackupStatusButton({super.key, required this.recordCount});
  final int recordCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = backupStatus(
        recordCount: recordCount, lastBackup: ref.watch(latestBackupProvider));
    final color = switch (status) {
      BackupStatus.ok => AppColors.backupOk,
      _ => AppColors.textSub,
    };
    return TestId(
      'btn_home_backup',
      selected: status == BackupStatus.ok,
      child: Semantics(
        button: true,
        label: switch (status) {
          BackupStatus.ok => '백업 · 최근에 백업했어요',
          BackupStatus.due => '백업 · 백업이 필요해요',
          BackupStatus.normal => '백업',
        },
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => showBackupGuideSheet(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                          status == BackupStatus.ok
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_outlined,
                          size: 22,
                          color: color),
                      if (status == BackupStatus.due)
                        Positioned(
                          right: -2,
                          top: -1,
                          child: Container(
                            key: const ValueKey('backup_due_dot'),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: AppColors.backupDue,
                                shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Text('백업', style: AppText.sub.copyWith(color: color)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 아래에서 올라오는 '백업 안내' 선택창 (공유 · 다운로드 선택창과 같은 모양, 오른쪽 위 X)
Future<void> showBackupGuideSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => const _BackupGuideSheet(),
    );

class _BackupGuideSheet extends ConsumerStatefulWidget {
  const _BackupGuideSheet();

  @override
  ConsumerState<_BackupGuideSheet> createState() => _BackupGuideSheetState();
}

class _BackupGuideSheetState extends ConsumerState<_BackupGuideSheet> {
  bool _working = false;

  /// 기존 수동 백업(설정의 [백업 파일 만들기])과 같다: 파일을 만들어 공유창으로
  Future<void> _backupNow() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final shared =
          await BackupService(DatabaseHelper.instance).createAndShareBackup();
      if (shared) {
        await ref.read(lastBackupProvider.notifier).markNow();
        if (mounted) showSnack(context, '백업 파일을 만들었어요. 안전한 곳에 꼭 보관하세요.');
      }
    } catch (e) {
      if (mounted) showSnack(context, '백업 파일을 만들지 못했어요: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _item(int n, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: AppColors.primarySoft, shape: BoxShape.circle),
              child: Text('$n',
                  style: AppText.sub.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.listName),
                  const SizedBox(height: 2),
                  Text(body, style: AppText.sub.copyWith(height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final last = ref.watch(latestBackupProvider);
    final auto = ref.watch(autoBackupProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 12, 12, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('백업 안내', style: AppText.appTitle),
                        const SizedBox(height: 4),
                        TestId('backup_last', child: Text(
                            last == null
                                ? '아직 백업이 없어요'
                                : '마지막 백업: ${formatBackupTime(last)}',
                            style: AppText.sub)),
                      ],
                    ),
                  ),
                ),
                TestId('backup_close', child: IconButton(
                  tooltip: '닫기',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                        color: AppColors.closeCircle, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 20, color: AppColors.icon),
                  ),
                )),
              ],
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.page - 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _item(1, '자동 백업 (${auto.enabled ? '켜짐' : '꺼짐'})',
                      '다운로드 > 경조사장부 폴더에 최근 7개를 보관해요'),
                  _item(2, '폰을 바꿀 때',
                      '백업 파일을 카톡 나에게 보내기나 드라이브에 저장 → 새 폰 설정 > 복원'),
                  _item(3, '구글 계정 백업',
                      '휴대폰의 구글 계정 백업이 켜져 있으면 새 폰에서 자동으로 복원될 수 있어요'),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 52,
                    child: TestId('btn_backup_now', child: FilledButton.icon(
                      onPressed: _working ? null : _backupNow,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('지금 백업 파일 만들기'),
                    )),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 52,
                    child: TestId('btn_backup_settings', child: OutlinedButton(
                      onPressed: () {
                        final nav = Navigator.of(context);
                        nav.pop();
                        nav.push(MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen()));
                      },
                      child: const Text('자동 백업 설정'),
                    )),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
