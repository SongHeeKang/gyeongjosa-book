import 'package:flutter/material.dart';

import '../models/constants.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../services/limits.dart';
import '../services/reception_file_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/test_id.dart';

/// 장부 보내기: 요약 메시지 · 장부 파일 중 고른다.
/// 받는 사람 화면에 무엇이 보이는지 미리 보여줘서, 요약 메시지만 보내고
/// 명단이 갔다고 생각하는 일이 없게 한다. (대신 받은 장부 · 내 행사 상세에서 연다)
class ReceptionSendScreen extends StatefulWidget {
  const ReceptionSendScreen({super.key, required this.package});
  final ReceptionPackage package;

  @override
  State<ReceptionSendScreen> createState() => _ReceptionSendScreenState();
}

class _ReceptionSendScreenState extends State<ReceptionSendScreen> {
  /// 처음에는 추천인 장부 파일을 골라 둔다
  bool _file = true;

  /// [안내 메시지 + 장부 파일 보내기]의 첫 번째(안내 메시지)를 보냈는지.
  /// 보냈으면 두 번째(장부 파일) 보내기 버튼을 보여준다.
  bool _guideSent = false;

  ReceptionPackage get _package => widget.package;

  Future<void> _sendSummary() async {
    try {
      await ReceptionFileService.shareSummary(_package);
    } catch (e) {
      if (mounted) showSnack(context, '보내지 못했어요: $e');
    }
  }

  Future<void> _sendFile({bool confirm = true}) async {
    if (confirm) {
      final ok = await confirmDialog(context,
          title: '장부 파일 보내기',
          message: '문자는 파일이 안 갈 수 있어요. 카카오톡이나 메일을 권장해요',
          okText: '파일 보내기');
      if (!ok) return;
    }
    try {
      await ReceptionFileService.share(_package);
    } catch (e) {
      if (mounted) showSnack(context, '보내지 못했어요: $e');
    }
  }

  /// 추천: 두 번에 나눠 보낸다. 카카오톡은 파일과 글을 한 번에 보내면 글이 빠지기도 한다.
  /// ① 안내 메시지를 보내고 앱으로 돌아오면 ② 장부 파일 보내기 버튼을 보여준다.
  Future<void> _sendGuideThenFile() async {
    try {
      final sent = await ReceptionFileService.shareSummary(_package);
      if (sent && mounted) setState(() => _guideSent = true);
    } catch (e) {
      if (mounted) showSnack(context, '보내지 못했어요: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _package.totals;
    final sides = [
      for (final s in _package.sides)
        if (s != ReceptionDefaults.noSide) s,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('장부 보내기')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 32),
        children: [
          const Text('받는 사람에게 이렇게 보여요', style: AppText.label),
          const SizedBox(height: 10),
          TestId(
            'send_summary',
            selected: !_file,
            child: _ChoiceCard(
              selected: !_file,
              title: '요약 메시지',
              onTap: () => setState(() => _file = false),
              preview: [
                '총 ${totals.count}명 · ${formatWon(totals.amount)}',
                for (final s in sides.take(2))
                  '$s ${_package.totalsFor(s).count}명 · ${formatWon(_package.totalsFor(s).amount)}',
              ],
              tag: '명단 없음 · 인원과 총액만',
              tagStrong: false,
            ),
          ),
          const SizedBox(height: 10),
          TestId(
            'send_file',
            selected: _file,
            child: _ChoiceCard(
              selected: _file,
              title: '장부 파일',
              recommended: true,
              onTap: () => setState(() => _file = true),
              preview: [
                for (final e in _package.entries.take(3))
                  '${e.name} · ${formatWon(e.amount)}',
                if (_package.entries.length > 3) '… 외 ${_package.entries.length - 3}명',
              ],
              tag: '전체 명단 · 앱에서 열기',
              tagStrong: true,
            ),
          ),
          const SizedBox(height: 24),
          if (!_file) ...[
            const Text('보낼 글', style: AppText.label),
            const SizedBox(height: 8),
            TestId(
              'send_summary_preview',
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  ReceptionFileService.summaryMessage(_package),
                  style: AppText.body.copyWith(height: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('이 메시지에는 손님 명단이 들어가지 않아요. 명단까지 넘겨주려면 장부 파일을 함께 보내세요',
                style: AppText.sub),
            const SizedBox(height: 8),
            TestId(
              'send_file_too',
              child: OutlinedButton.icon(
                onPressed: _sendFile,
                icon: const Icon(Icons.insert_drive_file_outlined),
                label: const Text('장부 파일도 보내기'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: AppSpacing.receptionButton,
              child: TestId(
                'send_go',
                child: FilledButton.icon(
                  onPressed: _sendSummary,
                  icon: const Icon(Icons.send),
                  label: const Text('요약 메시지 보내기'),
                ),
              ),
            ),
          ] else ...[
            TestId('send_receiver_guide',
                child: _ReceiverGuide(count: _package.totals.count)),
            const SizedBox(height: 16),
            if (_guideSent) ...[
              TestId(
                'send_step2',
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('② 이제 장부 파일을 같은 방에 보내세요',
                          style: AppText.sectionTitle
                              .copyWith(color: AppColors.primary)),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: AppSpacing.receptionButton,
                        child: TestId(
                          'send_step2_file',
                          child: FilledButton.icon(
                            onPressed: () => _sendFile(confirm: false),
                            icon: const Icon(Icons.insert_drive_file_outlined),
                            label: const Text('장부 파일 보내기'),
                          ),
                        ),
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
                'send_go',
                child: FilledButton.icon(
                  onPressed: _sendGuideThenFile,
                  icon: const Icon(Icons.send),
                  label: const Text('안내 메시지 + 장부 파일 보내기'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: AppSpacing.receptionButton,
                    child: TestId(
                      'send_file_only',
                      child: OutlinedButton(
                        onPressed: _sendFile,
                        child: const Text('장부 파일만'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: AppSpacing.receptionButton,
                    child: TestId(
                      'send_summary_only',
                      child: OutlinedButton(
                        onPressed: _sendSummary,
                        child: const Text('요약 메시지만'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 장부 파일을 보낼 때, 받는 사람이 여는 방법과 주의할 점
class _ReceiverGuide extends StatelessWidget {
  const _ReceiverGuide({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    const steps = [
      '① 앱 설치',
      "② 파일을 눌러 '경조사 장부'로 열기",
      '③ [가져오기]',
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('받는 사람은 이렇게 열어요', style: AppText.sectionTitle),
          const SizedBox(height: 8),
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(s, style: AppText.body),
            ),
          const SizedBox(height: 6),
          Text('무료는 ${FreeLimits.people}명까지 가져올 수 있어요(이 장부 $count명)',
              style: AppText.sub),
          const Text('카카오톡 파일은 보관 기간이 지나면 받을 수 없어요',
              style: AppText.sub),
        ],
      ),
    );
  }
}

/// 보내기 방식 카드: 제목 + 받는 사람 화면 미니 예시 + 표시
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.title,
    required this.onTap,
    required this.preview,
    required this.tag,
    required this.tagStrong,
    this.recommended = false,
  });
  final bool selected;
  final String title;
  final VoidCallback onTap;
  final List<String> preview;
  final String tag;

  /// true면 포인트색 표시(장부 파일), false면 회색 표시(요약 메시지)
  final bool tagStrong;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primarySoft : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                      size: 22,
                      color: selected ? AppColors.primary : AppColors.textSub),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title, style: AppText.sectionTitle)),
                  if (recommended)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('추천',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // 받는 사람 화면 미니 예시
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in preview)
                      Text(line,
                          style: AppText.sub.copyWith(color: AppColors.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(tag,
                        style: AppText.sub.copyWith(
                            fontWeight: FontWeight.w700,
                            color: tagStrong ? AppColors.primary : AppColors.textSub)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
