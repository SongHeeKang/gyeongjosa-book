import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/screen_coach.dart';
import 'onboarding_screen.dart';

/// 설정 > 사용 방법: 처음 4장 가이드, 화면별 도움말 목록, 처음부터 다시 보기
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('사용 방법')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ListTile(
            leading: const Icon(Icons.menu_book_outlined, size: 24),
            title: const Text('처음 4장 가이드'),
            subtitle: const Text('앱을 처음 열 때 본 안내를 다시 봐요'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const OnboardingScreen(replay: true))),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt, size: 24),
            title: const Text('도움말 처음부터 다시 보기'),
            subtitle: const Text('각 화면에 다시 들어가면 도움말이 떠요'),
            onTap: () async {
              await resetCoachMarks(ref.read(prefsProvider));
              if (context.mounted) {
                showSnack(context, '각 화면에 다시 들어가면 도움말이 보여요.');
              }
            },
          ),
          const SizedBox(height: 12),
          const AppDivider(),
          const SectionTitle('화면별 도움말'),
          for (final screen in CoachScreen.values)
            ExpansionTile(
              title: Text(screen.title, style: AppText.listName),
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              childrenPadding: const EdgeInsets.fromLTRB(
                  AppSpacing.page, 0, AppSpacing.page, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              shape: const Border(),
              collapsedShape: const Border(),
              children: [
                for (final m in screen.marks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('· ${m.text}', style: AppText.body),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
