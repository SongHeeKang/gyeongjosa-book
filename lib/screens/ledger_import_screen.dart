import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ledger_text_format.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import 'event_detail_screen.dart';
import 'reception_import_screen.dart';

/// 장부 가져오기를 연다. 내 행사 상세에서 열면 그 행사에 합치는 것을 기본으로 고른다.
Future<void> openLedgerImport(BuildContext context, {int? eventId}) =>
    Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => LedgerImportScreen(eventId: eventId)));

/// 장부 가져오기: 받은 장부 메시지를 복사해 [붙여넣어 가져오기].
/// 클립보드는 이 버튼을 눌렀을 때만 읽는다(자동으로 읽지 않음).
/// 나눠 받은 메시지는 하나씩 차례로 붙여 넣으면 같은 내 행사로 합쳐진다.
/// 예전 JSON 장부 파일은 맨 아래 작은 [예전 장부 파일 가져오기]로만 가져온다.
class LedgerImportScreen extends StatefulWidget {
  const LedgerImportScreen({super.key, this.eventId});

  /// 합칠 내 행사 (내 행사 상세에서 열었을 때)
  final int? eventId;

  @override
  State<LedgerImportScreen> createState() => _LedgerImportScreenState();
}

class _LedgerImportScreenState extends State<LedgerImportScreen> {
  /// 방금 가져온 결과 (행사 id, 안내 문구)
  ({int eventId, String message})? _done;

  Future<void> _alert(String title, String message) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
          ],
        ),
      );

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      await _alert('복사한 메시지가 없어요',
          '카카오톡 · 문자에서 받은 장부 메시지를 길게 눌러 [복사]한 뒤 다시 눌러 주세요.');
      return;
    }
    final parsed = LedgerText.parse(text);
    if (parsed == null || parsed.count == 0) {
      await _alert('장부 메시지가 아니에요',
          "'[경조사 장부] … 받은 명단'으로 시작하는 메시지를 통째로 복사해 주세요.");
      return;
    }
    final result = await Navigator.push<ImportResult>(
        context,
        MaterialPageRoute<ImportResult>(
            builder: (_) => ReceptionImportScreen(
                  package: parsed.toPackage(),
                  initialEventId: widget.eventId,
                  unreadableLines: parsed.unreadable,
                  returnResult: true,
                )));
    if (result == null || !mounted) return;
    setState(() => _done = (
          eventId: result.eventId,
          message: "'${result.title}'에 ${result.count}명을 가져왔어요",
        ));
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
    return Scaffold(
      appBar: AppBar(title: const Text('장부 가져오기')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 32),
        children: [
          const Text('받은 장부 메시지를 붙여 넣어 가져와요',
              style: AppText.sectionTitle),
          const SizedBox(height: 12),
          for (final step in const [
            '① 카카오톡 · 문자에서 받은 장부 메시지를 길게 눌러 [복사]',
            '② 아래 [붙여넣어 가져오기]',
            '③ 인원 · 총액을 확인하고 가져오기',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(step, style: AppText.body),
            ),
          const SizedBox(height: 4),
          const Text('나눠 받은 메시지(1/2, 2/2…)는 하나씩 차례로 붙여 넣으면 한 장부로 합쳐져요. '
              '같은 메시지를 두 번 붙여도 두 번 저장되지 않아요.',
              style: AppText.sub),
          const SizedBox(height: 24),
          if (done != null) ...[
            TestId(
              'paste_import_done',
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(done.message,
                        style: AppText.sectionTitle
                            .copyWith(color: AppColors.primary)),
                    const SizedBox(height: 4),
                    const Text('다음 메시지가 있으면 복사해서 한 번 더 붙여 넣으세요.',
                        style: AppText.body),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  EventDetailScreen(eventId: done.eventId))),
                      child: const Text('행사 보기'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            height: AppSpacing.receptionButton,
            child: TestId(
              'btn_paste_import',
              child: FilledButton.icon(
                onPressed: _paste,
                icon: const Icon(Icons.content_paste),
                label: const Text('붙여넣어 가져오기'),
              ),
            ),
          ),
          const SizedBox(height: 40),
          Center(
            child: TestId(
              'btn_import_old_file',
              child: TextButton(
                onPressed: () =>
                    pickAndOpenImport(context, eventId: widget.eventId),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSub,
                    textStyle: AppText.sub),
                child: const Text('예전 장부 파일 가져오기'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
