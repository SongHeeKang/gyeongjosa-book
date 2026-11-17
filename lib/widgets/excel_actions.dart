import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/providers.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'test_id.dart';

const _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// 엑셀 파일 버튼을 누른 뒤: [공유하기] [폰에 저장] [취소].
/// [build]는 고른 뒤에 파일 내용을 만든다. 공유를 마치면 [afterShare]를 부른다
/// (다른 사람 행사의 보관 · 지우기 질문).
Future<void> showExcelActions(
  BuildContext context, {
  required String fileName,
  required Future<Uint8List> Function() build,
  Future<void> Function()? afterShare,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.page, 0, AppSpacing.page, 4),
            child: Text(fileName,
                style: AppText.sub, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          TestId('excel_share', child: ListTile(
            minTileHeight: 64,
            leading: const Icon(Icons.share_outlined, size: 26, color: AppColors.primary),
            title: const Text('공유하기', style: AppText.sectionTitle),
            subtitle: const Text('카톡 · 문자 · 메일 · 드라이브 등으로 파일 보내기'),
            onTap: () => Navigator.pop(ctx, 'share'),
          )),
          TestId('excel_save', child: ListTile(
            minTileHeight: 64,
            leading: const Icon(Icons.download_outlined, size: 26, color: AppColors.primary),
            title: const Text('폰에 저장', style: AppText.sectionTitle),
            subtitle: const Text('다운로드 폴더에 저장해요'),
            onTap: () => Navigator.pop(ctx, 'save'),
          )),
          TestId('excel_cancel', child: ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.close, size: 26),
            title: const Text('취소'),
            onTap: () => Navigator.pop(ctx),
          )),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  try {
    final bytes = await build();
    if (action == 'share') {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      // 제목(subject)은 넣지 않는다
      final result = await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path, mimeType: _xlsxMime)]));
      if (result.status != ShareResultStatus.dismissed && afterShare != null) {
        await waitUntilAppResumed();
        await afterShare();
      }
    } else {
      // 저장소 권한 없이 시스템 저장 창으로 저장한다 (기본 다운로드 폴더)
      final saved = await FilePicker.saveFile(
          fileName: fileName, bytes: bytes, mimeType: _xlsxMime);
      if (saved != null && context.mounted) showSnack(context, '저장했어요.');
    }
  } catch (e) {
    if (context.mounted) showSnack(context, '엑셀 파일을 만들지 못했어요: $e');
  }
}

/// 공유창에서 다른 앱으로 갔다가 이 앱으로 돌아올 때까지 기다린다.
Future<void> waitUntilAppResumed() async {
  final state = WidgetsBinding.instance.lifecycleState;
  if (state == AppLifecycleState.resumed || state == null) return;
  final back = Completer<void>();
  final listener = AppLifecycleListener(onResume: () {
    if (!back.isCompleted) back.complete();
  });
  await back.future;
  listener.dispose();
}

/// 다른 사람 행사를 보낸 뒤(글자 · 엑셀 모두): "이 장부를 보관할까요, 지울까요?"
Future<void> askKeepOrDeleteReception(
  BuildContext context,
  WidgetRef ref, {
  required String receptionId,
  required int count,
}) async {
  final delete = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('이 장부를 보관할까요, 지울까요?'),
      content: const Text('보낸 장부는 받은 분이 앱으로 가져갈 수 있어요. '
          '이 폰에서 지워도 내 사람 탭 · 통계에는 영향이 없어요.'),
      actions: [
        TextButton(
            key: const ValueKey('send_delete'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('지우기')),
        FilledButton(
            key: const ValueKey('send_keep'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('보관')),
      ],
    ),
  );
  if (delete != true || !context.mounted) return;
  final ok = await confirmDialog(context,
      title: '장부를 지울까요?',
      message: '받은 명단 $count명이 이 폰에서 지워져요. 되돌릴 수 없어요.',
      okText: '지우기',
      destructive: true);
  if (!ok || !context.mounted) return;
  await ref.read(repositoryProvider).deleteReception(receptionId);
  ref.refreshData();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  Navigator.of(context).popUntil((route) => route.isFirst);
  messenger.showSnackBar(const SnackBar(content: Text('장부를 지웠어요.')));
}

/// [엑셀] · [엑셀 파일] 버튼. 기록이 없으면 흐리게 두고 누르면 "아직 기록이 없어요".
class ExcelButton extends StatelessWidget {
  const ExcelButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.compact = false,
  });
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  /// 앱 위쪽 막대처럼 좁은 자리에 쓰는 글자 버튼
  final bool compact;

  void _tap(BuildContext context) =>
      enabled ? onPressed() : showSnack(context, '아직 기록이 없어요.');

  @override
  Widget build(BuildContext context) {
    final color = enabled ? null : AppColors.textSub.withValues(alpha: 0.5);
    if (compact) {
      return TextButton.icon(
        onPressed: () => _tap(context),
        style: TextButton.styleFrom(
          foregroundColor: enabled ? AppColors.icon : color,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(44, 44),
        ),
        icon: const Icon(Icons.grid_on_outlined, size: 22),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _tap(context),
      style: OutlinedButton.styleFrom(foregroundColor: color),
      icon: const Icon(Icons.grid_on_outlined),
      label: Text(label),
    );
  }
}
