import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/database_helper.dart';
import '../data/providers.dart';
import '../data/sample_data.dart';
import '../services/app_config.dart';
import '../services/backup_service.dart';
import '../services/csv_service.dart';
import '../services/format.dart';
import '../services/notification_service.dart';
import '../services/pro_service.dart';
import '../services/purchase_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/pro_gate.dart';

final _appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _backup = BackupService(DatabaseHelper.instance);
  bool _working = false;

  Future<void> _run(Future<void> Function() task) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _makeBackup() => _run(() async {
        try {
          final shared = await _backup.createAndShareBackup();
          if (shared) {
            await ref.read(lastBackupProvider.notifier).markNow();
            if (mounted) showSnack(context, '백업 파일을 만들었어요. 안전한 곳에 꼭 보관하세요.');
          }
        } catch (e) {
          if (mounted) showSnack(context, '백업 파일을 만들지 못했어요: $e');
        }
      });

  Future<void> _restore() => _run(() async {
        try {
          final path = await _backup.pickAndValidate();
          if (path == null || !mounted) return;
          final ok = await confirmDialog(context,
              title: '백업에서 복원',
              message: '현재 기록이 백업 파일 내용으로 바뀝니다.\n계속할까요?',
              okText: '복원',
              destructive: true);
          if (!ok) return;
          await _backup.restoreFrom(path);
          ref.refreshData();
          final events = await ref.read(repositoryProvider).allEvents();
          await NotificationService.instance.resyncAll(events);
          if (mounted) showSnack(context, '복원했어요.');
        } on FormatException catch (e) {
          if (mounted) {
            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('복원할 수 없어요'),
                content: Text('${e.message}\n\n기존 기록은 그대로 남아 있어요.'),
                actions: [
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('확인')),
                ],
              ),
            );
          }
        } catch (e) {
          if (mounted) showSnack(context, '복원 중 오류가 났어요: $e');
        }
      });

  Future<void> _exportCsv() async {
    if (!await ensurePro(context, ref,
        reason: '엑셀(CSV) 내보내기는 프로 기능이에요.')) {
      return;
    }
    await _run(() async {
      final records = await ref.read(repositoryProvider).allRecords();
      if (records.isEmpty) {
        if (mounted) showSnack(context, '내보낼 내역이 없어요.');
        return;
      }
      await CsvService.exportAndShare(records);
    });
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showSnack(context, '열 수 없어요: $uri');
  }

  @override
  Widget build(BuildContext context) {
    final lastBackup = ref.watch(lastBackupProvider);
    final pro = ref.watch(proProvider);
    final purchase = ref.watch(purchaseProvider);
    final version = ref.watch(_appVersionProvider).value ?? '';

    ref.listen(purchaseProvider, (prev, next) {
      if (next.message != null && next.messageId != prev?.messageId) {
        showSnack(context, next.message!);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: AbsorbPointer(
        absorbing: _working,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (_working) const LinearProgressIndicator(),
            const SectionTitle('백업 · 복원'),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined, size: 24),
              title: const Text('백업 파일 만들기'),
              subtitle: Text(lastBackup == null
                  ? '아직 백업한 적이 없어요\n카카오톡 "나에게 보내기" 등으로 보관하세요'
                  : '마지막 백업: ${formatDate(lastBackup)}'),
              isThreeLine: lastBackup == null,
              onTap: _makeBackup,
            ),
            ListTile(
              leading: const Icon(Icons.restore, size: 24),
              title: const Text('백업에서 복원'),
              subtitle: const Text('새 폰에서 백업 파일을 골라 불러와요'),
              onTap: _restore,
            ),
            const ListTile(
              leading: Icon(Icons.info_outline, size: 24),
              title: Text('자동 백업'),
              subtitle: Text(
                  '휴대폰의 Google 백업이 켜져 있으면 기록이 내 Google 계정에 자동 백업되고, 새 폰을 설정할 때 복원돼요.'),
            ),
            const SizedBox(height: 12),
            const AppDivider(),
            const SectionTitle('내보내기'),
            ListTile(
              leading: const Icon(Icons.table_view, size: 24),
              title: Row(children: [
                const Text('엑셀(CSV)로 내보내기'),
                if (!pro.isPro) ...[const SizedBox(width: 8), const ProBadge()],
              ]),
              subtitle: const Text('이름, 관계, 보냄/받음, 금액, 행사, 날짜, 메모'),
              onTap: _exportCsv,
            ),
            const SizedBox(height: 12),
            const AppDivider(),
            const SectionTitle('프로'),
            ListTile(
              leading: Icon(
                  pro.isPro ? Icons.workspace_premium : Icons.lock_open,
                  size: 24,
                  color: pro.isPro ? AppColors.primary : null),
              title: Text(pro.isPro ? '프로 사용 중' : '프로 평생 이용권'),
              subtitle: Text(pro.isPro
                  ? '모든 기능을 쓸 수 있어요. 감사합니다!'
                  : '${purchase.priceText} · 한 번 결제로 평생 사용'),
              onTap: pro.isPro ? null : () => showPaywall(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.replay, size: 24),
              title: const Text('구매 복원'),
              subtitle: const Text('폰을 바꿨다면 눌러 주세요'),
              onTap: purchase.busy
                  ? null
                  : () => ref.read(purchaseProvider.notifier).restore(),
            ),
            const SizedBox(height: 12),
            const AppDivider(),
            const SectionTitle('기타'),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined, size: 24),
              title: const Text('개인정보처리방침'),
              subtitle: const Text('모든 기록은 이 폰에만 저장돼요'),
              onTap: () => _open(Uri.parse(AppConfig.privacyPolicyUrl)),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline, size: 24),
              title: const Text('문의하기'),
              onTap: () => _open(Uri(
                scheme: 'mailto',
                path: AppConfig.supportEmail,
                query: 'subject=${Uri.encodeComponent('[경조사 장부] 문의')}',
              )),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, size: 24),
              title: const Text('앱 버전'),
              trailing: Text(version, style: AppText.sub),
            ),
            if (kDebugMode) ..._devTools(pro),
          ],
        ),
      ),
    );
  }

  /// 개발 모드(flutter run)에서만 보이는 테스트 도구
  List<Widget> _devTools(ProState pro) => [
        const SizedBox(height: 12),
        const AppDivider(),
        const SectionTitle('개발 모드 전용'),
        SwitchListTile(
          secondary: const Icon(Icons.science_outlined, size: 24),
          title: const Text('isPro 켜기/끄기 (테스트)', style: AppText.listName),
          subtitle: Text(pro.devOverride == null
              ? '실제 구매 상태 사용 중'
              : '테스트 값 사용 중 · 아래 [isPro 테스트 값 해제]로 되돌리기'),
          value: pro.isPro,
          onChanged: (v) => ref.read(proProvider.notifier).setDevOverride(v),
        ),
        ListTile(
          leading: const Icon(Icons.dataset_outlined, size: 24),
          title: const Text('샘플 데이터 넣기'),
          subtitle: const Text('사람 5명, 내역 10개'),
          onTap: () => _run(() async {
            await insertSampleData(ref.read(repositoryProvider));
            ref.refreshData();
            if (mounted) showSnack(context, '샘플 데이터를 넣었어요.');
          }),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined, size: 24),
          title: const Text('알림 테스트 (지금 바로)'),
          onTap: () async {
            await NotificationService.instance
                .ensurePermission(context, ref.read(prefsProvider));
            await NotificationService.instance.showTest();
          },
        ),
        ListTile(
          leading: const Icon(Icons.restart_alt, size: 24),
          title: const Text('isPro 테스트 값 해제'),
          onTap: () => ref.read(proProvider.notifier).setDevOverride(null),
        ),
      ];
}
