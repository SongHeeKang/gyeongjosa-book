import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/reception.dart';
import '../services/ledger_text_format.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/share_download.dart';
import '../widgets/test_id.dart';

/// 장부 보내기: 저장된 모든 값을 글자로 보낸다(파일 없음, 모두 무료).
/// 보낼 글 미리보기 + [가나다순 / 받은 순서] + [메모 포함] + [복사] [보내기].
/// 100명([kShareChunkSize])을 넘으면 나눠서 [1/2 보내기] [2/2 보내기]… 차례로 보낸다.
/// 다른 사람 행사([receptionId])는 마지막 조각까지 보낸 뒤 앱으로 돌아오면 보관 · 지우기를 묻는다.
/// (내 행사 상세 · 다른 사람 행사 상세 · 받기 끝내기 화면에서 연다)
class ReceptionSendScreen extends ConsumerStatefulWidget {
  const ReceptionSendScreen({super.key, required this.package, this.receptionId});
  final ReceptionPackage package;

  /// 다른 사람 행사면 그 장부 id (보낸 뒤 보관 · 지우기를 묻는다)
  final String? receptionId;

  /// 테스트에서 공유창 대신 쓴다. 보냈으면 true.
  @visibleForTesting
  static Future<bool> Function(String text)? debugShare;

  @override
  ConsumerState<ReceptionSendScreen> createState() =>
      _ReceptionSendScreenState();
}

class _ReceptionSendScreenState extends ConsumerState<ReceptionSendScreen> {
  LedgerOrder _order = LedgerOrder.name;
  bool _includeMemo = true;

  /// 보낸 메시지 번호(0부터)
  final _sent = <int>{};
  bool _sending = false;

  List<String> get _parts => LedgerText.build(widget.package,
      order: _order, includeMemo: _includeMemo);

  bool get _hasMemo =>
      widget.package.entries.any((e) => (e.memo ?? '').trim().isNotEmpty);

  /// 순서나 메모를 바꾸면 나뉜 내용이 달라지므로 처음부터 다시 보낸다.
  void _changeOptions(VoidCallback change) => setState(() {
        change();
        _sent.clear();
      });

  /// 미리보기 · 복사할 메시지: 아직 안 보낸 첫 메시지
  int _current(int count) {
    for (var i = 0; i < count; i++) {
      if (!_sent.contains(i)) return i;
    }
    return 0;
  }

  Future<bool> _share(String text) async {
    if (ReceptionSendScreen.debugShare case final share?) return share(text);
    // 제목(subject)은 넣지 않는다. 카카오톡이 제목과 본문을 합쳐 첫 줄이 두 번 들어가기 때문.
    final result = await SharePlus.instance.share(ShareParams(text: text));
    return result.status != ShareResultStatus.dismissed;
  }

  Future<void> _send(int index) async {
    if (_sending) return;
    final parts = _parts;
    setState(() => _sending = true);
    try {
      final sent = await _share(parts[index]);
      if (!mounted || !sent) return;
      setState(() => _sent.add(index));
      if (_sent.length == parts.length && widget.receptionId != null) {
        await waitUntilAppResumed();
        if (mounted) await _askKeepOrDelete();
      }
    } catch (e) {
      if (mounted) showSnack(context, '보내지 못했어요: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _askKeepOrDelete() => askKeepOrDeleteReception(context, ref,
      receptionId: widget.receptionId!, count: widget.package.totals.count);

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showSnack(context, '복사했어요. 카카오톡 · 문자에 붙여 넣으세요.');
  }

  Widget _choice(String id, String label, bool selected, VoidCallback onTap) =>
      Expanded(
        child: TestId(
          id,
          selected: selected,
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                backgroundColor: selected ? AppColors.primarySoft : null,
                foregroundColor: selected ? AppColors.primary : null,
                side: selected
                    ? const BorderSide(color: AppColors.primary, width: 1.5)
                    : null,
              ),
              child: Text(label),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final parts = _parts;
    final many = parts.length > 1;
    final current = _current(parts.length);
    return Scaffold(
      appBar: AppBar(title: const Text('장부 보내기')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 32),
        children: [
          Text(
              many
                  ? '${widget.package.totals.count}명이라 ${parts.length}개로 나눠 보내요. 차례로 눌러 주세요.'
                  : '모든 명단을 글자로 보내요. 카카오톡 · 문자 · 메일 아무 앱이나 골라요.',
              style: AppText.sub),
          const SizedBox(height: 16),
          const Text('명단 순서', style: AppText.label),
          const SizedBox(height: 8),
          Row(children: [
            _choice('send_order_name', '가나다순', _order == LedgerOrder.name,
                () => _changeOptions(() => _order = LedgerOrder.name)),
            const SizedBox(width: 8),
            _choice('send_order_received', '받은 순서',
                _order == LedgerOrder.received,
                () => _changeOptions(() => _order = LedgerOrder.received)),
          ]),
          if (_hasMemo)
            TestId(
              'send_include_memo',
              selected: _includeMemo,
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _includeMemo,
                onChanged: (v) => _changeOptions(() => _includeMemo = v ?? true),
                title: const Text('메모 포함', style: AppText.body),
              ),
            )
          else
            const SizedBox(height: 16),
          Text(many ? '보낼 글 (${current + 1}/${parts.length})' : '보낼 글',
              style: AppText.label),
          const SizedBox(height: 8),
          TestId(
            'send_preview',
            child: Container(
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: SelectableText(parts[current],
                    style: AppText.body.copyWith(height: 1.5)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!many)
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: AppSpacing.receptionButton,
                  child: TestId(
                    'send_copy',
                    child: OutlinedButton.icon(
                      onPressed: () => _copy(parts.first),
                      icon: const Icon(Icons.copy),
                      label: const Text('복사'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: AppSpacing.receptionButton,
                  child: TestId(
                    'send_go',
                    child: FilledButton.icon(
                      onPressed: _sending ? null : () => _send(0),
                      icon: Icon(_sent.contains(0) ? Icons.check : Icons.send),
                      label: Text(_sent.contains(0) ? '보냈어요 · 다시 보내기' : '보내기'),
                    ),
                  ),
                ),
              ),
            ])
          else ...[
            SizedBox(
              height: 48,
              child: TestId(
                'send_copy',
                child: OutlinedButton.icon(
                  onPressed: () => _copy(parts[current]),
                  icon: const Icon(Icons.copy),
                  label: Text('${current + 1}/${parts.length} 복사'),
                ),
              ),
            ),
            for (var i = 0; i < parts.length; i++) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: AppSpacing.receptionButton,
                child: TestId(
                  'send_part_${i + 1}',
                  selected: _sent.contains(i),
                  child: i == current && !_sent.contains(i)
                      ? FilledButton.icon(
                          onPressed: _sending ? null : () => _send(i),
                          icon: const Icon(Icons.send),
                          label: Text('${i + 1}/${parts.length} 보내기'),
                        )
                      : OutlinedButton.icon(
                          onPressed: _sending ? null : () => _send(i),
                          icon: Icon(_sent.contains(i) ? Icons.check : Icons.send),
                          label: Text(_sent.contains(i)
                              ? '${i + 1}/${parts.length} 보냈어요 ✓'
                              : '${i + 1}/${parts.length} 보내기'),
                        ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
