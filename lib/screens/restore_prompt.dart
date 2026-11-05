import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database_helper.dart';
import '../data/providers.dart';
import '../services/auto_backup_service.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// 검사가 끝난 백업 파일로 복원하고 화면과 알림을 새로 맞춘다.
Future<void> restoreBackupFile(
    WidgetRef ref, BackupService backup, String path) async {
  await ref.read(autoBackupProvider.notifier).beforeRestore();
  await backup.restoreFrom(path);
  ref.refreshData();
  final events = await ref.read(repositoryProvider).allEvents();
  await NotificationService.instance.resyncAll(events);
}

/// 앱을 처음 켰는데 기록이 비어 있으면 이전 백업을 불러올지 한 번 묻는다.
class RestorePromptGate extends ConsumerStatefulWidget {
  const RestorePromptGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<RestorePromptGate> createState() => _RestorePromptGateState();
}

class _RestorePromptGateState extends ConsumerState<RestorePromptGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final prefs = ref.read(prefsProvider);
    if (prefs.getBool(PrefKeys.restorePromptDone) ?? false) return;
    final hasData = await ref.read(repositoryProvider).hasAnyData();
    if (!mounted) return;
    if (!hasData) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _RestoreDialog(),
      );
    }
    await prefs.setBool(PrefKeys.restorePromptDone, true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _RestoreDialog extends ConsumerStatefulWidget {
  const _RestoreDialog();

  @override
  ConsumerState<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends ConsumerState<_RestoreDialog> {
  final _backup = BackupService(DatabaseHelper.instance);
  bool _working = false;
  String? _error;

  Future<void> _pick() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final path = await _backup.pickAndValidate();
      if (path == null) return;
      await restoreBackupFile(ref, _backup, path);
      if (mounted) Navigator.pop(context);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '불러오지 못했어요: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('이전 백업을 불러올까요?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('다운로드 > 경조사장부 폴더에 자동 백업 파일이 있을 수 있어요.',
                style: AppText.body),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error, style: AppText.warning),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: AppSpacing.receptionButton,
              child: FilledButton(
                onPressed: _working ? null : _pick,
                child: const Text('백업 파일 고르기'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: AppSpacing.receptionButton,
              child: OutlinedButton(
                onPressed: _working ? null : () => Navigator.pop(context),
                child: const Text('새로 시작'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
