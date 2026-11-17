import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/providers.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../models/person.dart';
import '../models/reception.dart';
import '../screens/reception_send_screen.dart';
import '../screens/text_share_screen.dart';
import '../services/event_package.dart';
import '../services/export_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'coach_mark.dart';
import 'common.dart';
import 'test_id.dart';

const _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// 공유하기 · 폰에 저장 (엑셀 · 텍스트, 모두 무료)
enum ExportMode { share, download }

/// 공유 · 다운로드할 범위. 홈 = 주고받은 내역, 행사 탭 = 행사 장부 전체, 행사 상세 = 그 행사 하나.
abstract class ExportTarget {
  /// 선택창에 보여줄 범위 한 줄 (예: '행사 장부 12개 전체')
  String get rangeLabel;
  String excelFileName(DateTime now);
  String textFileName(DateTime now);
  Future<Uint8List> buildExcel(DateTime now);

  /// 다운로드할 .txt 내용 (나누지 않음)
  Future<String> buildTextFile(DateTime now);

  /// 글자 공유 화면을 연다 (나눠 보내기 · 보낸 뒤 질문은 그 화면이 맡는다)
  Future<void> shareText(BuildContext context);

  /// 엑셀 파일을 공유하고 앱으로 돌아온 뒤 할 일 (다른 사람 행사 상세: 보관 · 지우기)
  Future<void> afterExcelShared(BuildContext context) async {}
}

/// 오른쪽 위 [공유] [다운로드] 아이콘. 꺼져 있으면 회색이고 눌러도 반응이 없다.
class ShareDownloadButtons extends StatelessWidget {
  const ShareDownloadButtons({
    super.key,
    required this.enabled,
    required this.target,
    this.spot,
  });
  final bool enabled;

  /// 누를 때 만든다 (데이터를 그때 읽는다)
  final ExportTarget Function() target;

  /// 도움말이 두 아이콘을 함께 가리킬 자리
  final CoachSpot? spot;

  @override
  Widget build(BuildContext context) {
    Widget button(String id, String tooltip, IconData icon, ExportMode mode) =>
        TestId(
          id,
          child: IconButton(
            tooltip: tooltip,
            color: AppColors.icon,
            disabledColor: AppColors.divider,
            icon: Icon(icon),
            onPressed: enabled
                ? () => showExportSheet(context, mode: mode, target: target())
                : null,
          ),
        );
    final row = Row(mainAxisSize: MainAxisSize.min, children: [
      button('btn_share', '공유하기', Icons.share_outlined, ExportMode.share),
      button('btn_download', '폰에 저장', Icons.download_outlined, ExportMode.download),
    ]);
    final s = spot;
    return s == null ? row : CoachTarget(spot: s, child: row);
  }
}

/// 아래에서 올라오는 선택창: 제목 + 범위 한 줄, 오른쪽 위 X, 아래에 큰 카드 두 개 [엑셀 파일] [텍스트].
/// 바깥을 누르거나 뒤로 가기로도 닫힌다.
Future<void> showExportSheet(
  BuildContext context, {
  required ExportMode mode,
  required ExportTarget target,
}) async {
  final share = mode == ExportMode.share;
  final choice = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: Padding(
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
                        Text(share ? '공유하기' : '폰에 저장', style: AppText.appTitle),
                        const SizedBox(height: 4),
                        TestId('export_range',
                            child: Text(target.rangeLabel, style: AppText.sub)),
                      ],
                    ),
                  ),
                ),
                // 누르는 영역 48dp, 연한 회색 동그라미 안 X
                TestId('export_close', child: IconButton(
                  tooltip: '닫기',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => Navigator.pop(ctx),
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
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _ExportCard(
                        id: 'export_excel',
                        icon: Icons.table_chart_outlined,
                        color: AppColors.exportExcel,
                        background: AppColors.exportExcelSoft,
                        title: '엑셀 파일',
                        detail: '표로 정리 · .xlsx',
                        onTap: () => Navigator.pop(ctx, 'excel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ExportCard(
                        id: 'export_text',
                        icon: Icons.chat_bubble_outline,
                        color: AppColors.exportText,
                        background: AppColors.exportTextSoft,
                        title: '텍스트',
                        detail: share ? '카톡 · 문자에 글자로' : '메모장에서 열리는 .txt',
                        onTap: () => Navigator.pop(ctx, 'text'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final now = DateTime.now();
  try {
    if (share && choice == 'text') {
      await target.shareText(context);
    } else if (share) {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, target.excelFileName(now)));
      await file.writeAsBytes(await target.buildExcel(now), flush: true);
      // 제목(subject)은 넣지 않는다
      final result = await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path, mimeType: _xlsxMime)]));
      if (result.status != ShareResultStatus.dismissed && context.mounted) {
        await waitUntilAppResumed();
        if (context.mounted) await target.afterExcelShared(context);
      }
    } else {
      // 저장소 권한 없이 시스템 저장 창으로 저장한다 (기본 다운로드 폴더)
      final excel = choice == 'excel';
      final saved = await FilePicker.saveFile(
        fileName: excel ? target.excelFileName(now) : target.textFileName(now),
        bytes: excel
            ? await target.buildExcel(now)
            : Uint8List.fromList(utf8.encode(await target.buildTextFile(now))),
        mimeType: excel ? _xlsxMime : 'text/plain',
      );
      if (saved != null && context.mounted) showSnack(context, '저장했어요.');
    }
  } catch (e) {
    if (context.mounted) showSnack(context, '파일을 만들지 못했어요: $e');
  }
}

/// 선택창의 큰 카드: 둥근 네모(40dp) 안 아이콘 + 굵은 제목 + 설명. 얇은 테두리, 누르면 물결.
class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.id,
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.detail,
    required this.onTap,
  });
  final String id;
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: AppColors.divider),
    );
    return TestId(id, child: Material(
      color: AppColors.background,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: background, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: 12),
              Text(title, style: AppText.sectionTitle),
              const SizedBox(height: 2),
              Text(detail, style: AppText.sub),
            ],
          ),
        ),
      ),
    ));
  }
}

// ───────────────────────── 범위별 대상 ─────────────────────────

/// 홈: 개인으로 보내고 받은 모든 내역
class HistoryExport extends ExportTarget {
  HistoryExport(this.ref, {required this.count});
  final WidgetRef ref;
  final int count;

  @override
  String get rangeLabel => '주고받은 내역 $count건 전체';
  @override
  String excelFileName(DateTime now) => ExportService.historyFileName(now);
  @override
  String textFileName(DateTime now) => ExportService.historyFileName(now, ext: 'txt');

  @override
  Future<Uint8List> buildExcel(DateTime now) async {
    final repo = ref.read(repositoryProvider);
    return ExportService.buildHistory(
      records: await repo.allRecords(),
      people: await repo.allPeople(),
      events: await repo.allEvents(),
      now: now,
    );
  }

  @override
  Future<String> buildTextFile(DateTime now) async => ExportService.historyText(
          records: await ref.read(repositoryProvider).allRecords(),
          now: now,
          chunkSize: 1 << 30)
      .single;

  @override
  Future<void> shareText(BuildContext context) async {
    final parts = ExportService.historyText(
        records: await ref.read(repositoryProvider).allRecords());
    if (!context.mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => TextShareScreen(
                title: '주고받은 내역 보내기',
                intro: '보기용 글이에요. 받는 분이 앱으로 가져올 수는 없어요.',
                parts: parts)));
  }
}

/// 행사 탭: 행사 장부 전체 (내 행사 · 다른 사람 행사). 보낸 뒤 보관 · 지우기는 묻지 않는다.
class AllEventsExport extends ExportTarget {
  AllEventsExport(this.ref, {required this.count});
  final WidgetRef ref;
  final int count;

  @override
  String get rangeLabel => '행사 장부 $count개 전체';
  @override
  String excelFileName(DateTime now) => ExportService.allEventsFileName(now);
  @override
  String textFileName(DateTime now) =>
      ExportService.allEventsFileName(now, ext: 'txt');

  /// 내 행사(받은 기록) + 아직 내 행사로 옮기지 않은 다른 사람 행사, 날짜 최신순
  Future<List<({ReceptionPackage package, LedgerExcel excel})>> _load() async {
    final repo = ref.read(repositoryProvider);
    final prefs = ref.read(prefsProvider);
    final people = {for (final p in await repo.allPeople()) p.id: p};
    final out = <({ReceptionPackage package, LedgerExcel excel})>[];
    for (final e in await repo.myEvents()) {
      final records = [
        for (final r in await repo.recordsForEvent(e.id!))
          if (!r.isSent) r,
      ];
      out.add((
        package: eventPackage(prefs, e, records),
        excel: LedgerExcel.fromEvent(e, records, people),
      ));
    }
    for (final s in await repo.receptionSummaries()) {
      if (s.reception.imported) continue;
      final pkg = await repo.getReceptionPackage(s.reception.id);
      if (pkg == null) continue;
      out.add((package: pkg, excel: LedgerExcel.fromReception(pkg)));
    }
    out.sort((a, b) => b.excel.date.compareTo(a.excel.date));
    return out;
  }

  @override
  Future<Uint8List> buildExcel(DateTime now) async =>
      ExportService.buildAllEvents([for (final l in await _load()) l.excel], now: now);

  @override
  Future<String> buildTextFile(DateTime now) async =>
      ExportService.ledgersTextFile([for (final l in await _load()) l.package]);

  @override
  Future<void> shareText(BuildContext context) async {
    final parts =
        ExportService.allEventsTextParts([for (final l in await _load()) l.package]);
    if (!context.mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => TextShareScreen(
                title: '행사 장부 전체 보내기',
                intro: '행사마다 메시지 하나씩 차례로 보내요. 100명이 넘는 행사는 나눠서 보내요.',
                parts: parts)));
  }
}

/// 내 행사 상세: 그 행사 하나
class MyEventExport extends ExportTarget {
  MyEventExport(this.ref, {required this.event, required this.records});
  final WidgetRef ref;
  final Event event;

  /// 받은 기록
  final List<GiftRecord> records;

  ReceptionPackage get _package =>
      eventPackage(ref.read(prefsProvider), event, records);

  Future<Map<int?, Person>> _people() async => {
        for (final p in await ref.read(repositoryProvider).allPeople()) p.id: p,
      };

  @override
  String get rangeLabel => '${event.title} · ${records.length}명';
  @override
  String excelFileName(DateTime now) =>
      ExportService.ledgerFileName(event.title, event.date);
  @override
  String textFileName(DateTime now) =>
      ExportService.ledgerFileName(event.title, event.date, ext: 'txt');

  @override
  Future<Uint8List> buildExcel(DateTime now) async => ExportService.buildLedger(
      LedgerExcel.fromEvent(event, records, await _people()),
      now: now);

  @override
  Future<String> buildTextFile(DateTime now) async =>
      ExportService.ledgersTextFile([_package]);

  @override
  Future<void> shareText(BuildContext context) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => ReceptionSendScreen(package: _package)));
}

/// 다른 사람 행사 상세 (받기 끝내기 화면): 그 행사 하나. 보낸 뒤 보관 · 지우기를 묻는다.
class ReceptionExport extends ExportTarget {
  ReceptionExport(this.ref, {required this.package});
  final WidgetRef ref;
  final ReceptionPackage package;

  @override
  String get rangeLabel =>
      '${package.reception.title} · ${package.totals.count}명';
  @override
  String excelFileName(DateTime now) =>
      ExportService.ledgerFileName(package.reception.title, package.reception.date);
  @override
  String textFileName(DateTime now) => ExportService.ledgerFileName(
      package.reception.title, package.reception.date,
      ext: 'txt');

  @override
  Future<Uint8List> buildExcel(DateTime now) async =>
      ExportService.buildLedger(LedgerExcel.fromReception(package), now: now);

  @override
  Future<String> buildTextFile(DateTime now) async =>
      ExportService.ledgersTextFile([package]);

  @override
  Future<void> shareText(BuildContext context) => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => ReceptionSendScreen(
              package: package, receptionId: package.reception.id)));

  @override
  Future<void> afterExcelShared(BuildContext context) =>
      askKeepOrDeleteReception(context, ref,
          receptionId: package.reception.id, count: package.totals.count);
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

