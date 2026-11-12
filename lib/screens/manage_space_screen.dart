import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database_helper.dart';
import '../data/repository.dart';
import '../services/backup_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// 안드로이드 설정의 '공간 관리'에서 열리는 안내 화면.
/// 앱 본체와 다른 Flutter 엔진에서 돌기 때문에 Riverpod 없이 혼자 동작한다.
class ManageSpaceScreen extends StatefulWidget {
  const ManageSpaceScreen({super.key, this.helper, this.onBackup});

  /// 테스트에서 바꿔 넣는다. 없으면 앱 본체와 분리된 DB 연결을 쓴다.
  final DatabaseHelper? helper;
  final Future<bool> Function()? onBackup;

  @override
  State<ManageSpaceScreen> createState() => _ManageSpaceScreenState();
}

class _ManageSpaceScreenState extends State<ManageSpaceScreen> {
  static const _channel = MethodChannel('gyeongjosa/manage_space');

  late final DatabaseHelper _helper =
      widget.helper ?? DatabaseHelper.separateConnection();
  late final _repository = Repository(_helper);

  ({int people, int records, int entries})? _counts;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final counts = (
        people: await _repository.countPeople(),
        records: await _repository.countRecords(),
        entries: await _repository.countReceptionEntries(),
      );
      if (mounted) setState(() => _counts = counts);
    } catch (e) {
      debugPrint('기록 수 확인 실패: $e');
    } finally {
      await _helper.close();
    }
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _backup() => _run(() async {
        try {
          final onBackup = widget.onBackup ??
              BackupService(_helper).createAndShareBackup;
          final shared = await onBackup();
          if (shared) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(
                PrefKeys.lastBackupAt, DateTime.now().toIso8601String());
            if (mounted) {
              showSnack(context, '백업 파일을 만들었어요. 안전한 곳에 꼭 보관하세요.');
            }
          }
        } catch (e) {
          if (mounted) showSnack(context, '백업 파일을 만들지 못했어요: $e');
        } finally {
          await _helper.close();
        }
      });

  Future<void> _deleteAll() async {
    final ok = await confirmDialog(context,
        title: '정말 모두 삭제할까요?',
        message: '이 폰의 모든 경조사 기록과 설정이 지워지고 앱이 종료돼요.\n되돌릴 수 없어요.',
        okText: '모두 삭제',
        destructive: true);
    if (!ok) return;
    await _run(() async {
      var cleared = false;
      try {
        cleared = await _channel.invokeMethod<bool>('clearAppData') ?? false;
      } on PlatformException catch (e) {
        debugPrint('앱 데이터 삭제 실패: $e');
      }
      if (!cleared && mounted) showSnack(context, '삭제하지 못했어요. 다시 시도해 주세요.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    return Scaffold(
      appBar: AppBar(title: const Text('앱 데이터 관리')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 32),
        children: [
          if (_working) const LinearProgressIndicator(),
          if (counts != null) ...[
            const FieldLabel('이 폰에 저장된 내용'),
            Text(
              [
                '사람 ${counts.people}명',
                '기록 ${counts.records}건',
                if (counts.entries > 0) '대신 받기 ${counts.entries}건',
              ].join(' · '),
              style: AppText.summaryAmount,
            ),
            const SizedBox(height: AppSpacing.section),
          ],
          const Text('앱 데이터를 지우면 모든 경조사 기록이 사라져요. 먼저 백업해 두세요',
              style: AppText.receptionName),
          const SizedBox(height: AppSpacing.section),
          SizedBox(
            height: AppSpacing.receptionButton,
            child: FilledButton(
              onPressed: _working ? null : _backup,
              child: const Text('백업 파일 만들기'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: AppSpacing.receptionButton,
            child: OutlinedButton(
              onPressed: _working ? null : SystemNavigator.pop,
              child: const Text('취소'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: AppSpacing.receptionButton,
            child: TextButton(
              onPressed: _working ? null : _deleteAll,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('그래도 모두 삭제'),
            ),
          ),
        ],
      ),
    );
  }
}
