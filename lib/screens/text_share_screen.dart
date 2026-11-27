import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/test_id.dart';

/// 여러 메시지로 나눈 글을 [1/5 보내기] [2/5 보내기]… 차례로 보낸다.
/// (홈의 주고받은 내역. 행사 하나는 장부 보내기 화면을 쓴다)
class TextShareScreen extends StatefulWidget {
  const TextShareScreen({
    super.key,
    required this.title,
    required this.intro,
    required this.parts,
  });
  final String title;
  final String intro;
  final List<String> parts;

  /// 테스트에서 공유창 대신 쓴다. 보냈으면 true.
  @visibleForTesting
  static Future<bool> Function(String text)? debugShare;

  @override
  State<TextShareScreen> createState() => _TextShareScreenState();
}

class _TextShareScreenState extends State<TextShareScreen> {
  final _sent = <int>{};
  bool _sending = false;

  int get _current {
    for (var i = 0; i < widget.parts.length; i++) {
      if (!_sent.contains(i)) return i;
    }
    return 0;
  }

  Future<void> _send(int index) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final text = widget.parts[index];
      final bool sent;
      if (TextShareScreen.debugShare case final share?) {
        sent = await share(text);
      } else {
        // 제목(subject)은 넣지 않는다
        final result = await SharePlus.instance.share(ShareParams(text: text));
        sent = result.status != ShareResultStatus.dismissed;
      }
      if (sent && mounted) setState(() => _sent.add(index));
    } catch (e) {
      if (mounted) showSnack(context, '보내지 못했어요: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.parts;
    final count = parts.length;
    final current = _current;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 32),
        children: [
          Text(
              count > 1
                  ? '${widget.intro}\n$count개로 나눠 보내요. 차례로 눌러 주세요.'
                  : widget.intro,
              style: AppText.sub),
          const SizedBox(height: 16),
          Text(count > 1 ? '보낼 글 (${current + 1}/$count)' : '보낼 글',
              style: AppText.label),
          const SizedBox(height: 8),
          TestId(
            'text_share_preview',
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
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: TestId(
              'text_share_copy',
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: parts[current]));
                  if (context.mounted) {
                    showSnack(context, '복사했어요. 카카오톡 · 문자에 붙여 넣으세요.');
                  }
                },
                icon: const Icon(Icons.copy),
                label: Text(count > 1 ? '${current + 1}/$count 복사' : '복사'),
              ),
            ),
          ),
          for (var i = 0; i < count; i++) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: AppSpacing.receptionButton,
              child: TestId(
                'text_share_part_${i + 1}',
                selected: _sent.contains(i),
                child: i == current && !_sent.contains(i)
                    ? FilledButton.icon(
                        onPressed: _sending ? null : () => _send(i),
                        icon: const Icon(Icons.send),
                        label: Text(count > 1 ? '${i + 1}/$count 보내기' : '보내기'),
                      )
                    : OutlinedButton.icon(
                        onPressed: _sending ? null : () => _send(i),
                        icon: Icon(_sent.contains(i) ? Icons.check : Icons.send),
                        label: Text(_sent.contains(i)
                            ? (count > 1 ? '${i + 1}/$count 보냈어요 ✓' : '보냈어요 · 다시 보내기')
                            : '${i + 1}/$count 보내기'),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
