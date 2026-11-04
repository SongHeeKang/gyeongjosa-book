import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// 첫 실행 가이드 3장. 설정의 [사용 방법]에서 다시 볼 수 있다.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.replay = false});

  /// 설정에서 다시 보는 경우: 끝나면 이전 화면으로 돌아간다.
  final bool replay;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _pages = [
    (
      '주고받은 마음, 잊지 않게',
      '누가 언제 얼마를 냈는지 사람별로 정리해요',
      _PersonPicture(),
    ),
    (
      '+ 버튼 하나면 돼요',
      '보냈어요 · 일정 추가 · 받은 돈 정리 · 행사장 접수',
      _ButtonPicture(),
    ),
    (
      '기록은 내 폰에만',
      '회원가입 없이 바로 시작, 백업 파일로 폰을 바꿔도 안전해요',
      _PhonePicture(),
    ),
  ];

  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    if (widget.replay) {
      Navigator.pop(context);
    } else {
      ref.read(onboardingSeenProvider.notifier).markSeen();
    }
  }

  void _next() => _controller.nextPage(
      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 4),
                child: TextButton(
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.textSub),
                  onPressed: _finish,
                  child: const Text('건너뛰기'),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  for (final (title, body, picture) in _pages)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.page),
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: picture,
                              ),
                            ),
                          ),
                          Text(title,
                              textAlign: TextAlign.center,
                              style: AppText.guideTitle),
                          const SizedBox(height: 10),
                          Text(body,
                              textAlign: TextAlign.center,
                              style: AppText.guideBody),
                          const SizedBox(height: AppSpacing.section),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _index ? AppColors.primary : AppColors.divider,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.page),
              child: _isLast
                  ? FilledButton(
                      onPressed: _finish, child: const Text('시작하기'))
                  : OutlinedButton(onPressed: _next, child: const Text('다음')),
            ),
          ],
        ),
      ),
    );
  }
}

/// 1장 그림: 사람 한 명의 보냄 · 받음
class _PersonPicture extends StatelessWidget {
  const _PersonPicture();

  @override
  Widget build(BuildContext context) {
    Widget row(String label, int amount, {required bool isSent}) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppText.sub)),
              Text(signedWon(amount, isSent: isSent),
                  style: AppText.listAmount
                      .copyWith(color: AppColors.amount(isSent))),
            ],
          ),
        );
    return Container(
      width: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.account_circle, size: 40, color: AppColors.primary),
              SizedBox(width: 10),
              Text('김철수', style: AppText.sectionTitle),
            ],
          ),
          row('보냄', 50000, isSent: true),
          row('받음', 100000, isSent: false),
        ],
      ),
    );
  }
}

/// 2장 그림: + 버튼과 선택지 4개
class _ButtonPicture extends StatelessWidget {
  const _ButtonPicture();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.card_giftcard, '보냈어요'),
      (Icons.event_outlined, '일정 추가'),
      (Icons.playlist_add, '받은 돈 정리'),
      (Icons.edit_note, '행사장 접수'),
    ];
    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (icon, label) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Icon(icon, size: 24, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Text(label, style: AppText.listName),
                ],
              ),
            ),
          const SizedBox(height: 8),
          IgnorePointer(
            child: ExcludeSemantics(
              child: PillActionButton(label: '기록하기', onPressed: () {}),
            ),
          ),
        ],
      ),
    );
  }
}

/// 3장 그림: 폰과 자물쇠
class _PhonePicture extends StatelessWidget {
  const _PhonePicture();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 150,
          height: 230,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.icon, width: 4),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            color: AppColors.primarySoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.lock, size: 42, color: AppColors.primary),
        ),
      ],
    );
  }
}
