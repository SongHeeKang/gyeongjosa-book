import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/common.dart';
import '../widgets/record_menu_sheet.dart';
import 'home_screen.dart';
import 'my_events_screen.dart';
import 'people_screen.dart';
import 'stats_screen.dart';

/// 하단 탭 4개(홈 · 사람 · 내 행사 · 통계)와 모든 탭 같은 자리의 [+ 기록하기]
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    PeopleScreen(),
    MyEventsScreen(),
    StatsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // 홈에 기록이 하나도 없을 때만 버튼 바로 위에 화살표를 띄운다
    final showArrow =
        _index == 0 && (ref.watch(homeProvider).value?.recent.isEmpty ?? false);
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButtonLocation: const PillFabLocation(),
      floatingActionButton: keyboardOpen
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showArrow)
                  const IgnorePointer(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Icon(Icons.south,
                          size: 40, color: AppColors.primary),
                    ),
                  ),
                PillActionButton(
                  label: '기록하기',
                  onPressed: () => showRecordMenu(context, ref),
                ),
              ],
            ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
