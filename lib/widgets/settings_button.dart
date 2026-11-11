import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';

/// 모든 탭 오른쪽 위 같은 자리의 설정 아이콘
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  /// 오른쪽 끝을 페이지 여백에 맞춘다 (아이콘 버튼 자체 여백 12를 뺀 값)
  static const trailingGap = SizedBox(width: AppSpacing.page - 12);

  @override
  Widget build(BuildContext context) {
    return TestId(
      'btn_settings',
      child: IconButton(
        tooltip: '설정',
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
      ),
    );
  }
}
