import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../services/notification_permission.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/coach_mark.dart';
import '../widgets/common.dart';
import '../widgets/record_menu_sheet.dart';
import '../widgets/screen_coach.dart';
import 'home_screen.dart';
import 'my_events_screen.dart';
import 'people_screen.dart';
import 'stats_screen.dart';

/// 하단 탭 4개(홈 · 사람 · 행사 · 통계)와 모든 탭 같은 자리의 기록하기 버튼
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;
  bool _menuOpen = false;

  static const _screens = [
    HomeScreen(),
    PeopleScreen(),
    MyEventsScreen(),
    StatsScreen(),
  ];

  /// 탭별 자동 도움말 (IndexedStack이라 탭을 처음 고를 때 띄운다)
  static const _tabCoach = [
    CoachScreen.home,
    CoachScreen.people,
    CoachScreen.myEvents,
    CoachScreen.stats,
  ];

  late final AppLifecycleListener _lifecycle;

  /// 이번 실행에서 알림 권한을 확인했는지 (앱을 켤 때 한 번)
  bool _permissionChecked = false;

  @override
  void initState() {
    super.initState();
    // 휴대폰 설정에서 알림을 켜고 돌아오면 바로 반영한다
    _lifecycle = AppLifecycleListener(
        onResume: () =>
            ref.read(notificationPermissionProvider.notifier).refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterStart());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// 앱을 켜면 알림 권한부터 확인한다. 이전 백업을 묻는 단계가 끝난 뒤에 묻고,
  /// 권한이 있으면 아무것도 묻지 않는다. 그다음 탭 도움말.
  Future<void> _afterStart() async {
    if (!mounted) return;
    if (!_permissionChecked && ref.read(restorePromptDoneProvider)) {
      _permissionChecked = true;
      await askNotificationPermission(context, ref, atLaunch: true);
    }
    _showTabCoach();
  }

  void _showTabCoach() {
    if (!mounted) return;
    final index = _index;
    showCoachOnce(context, ref.read(prefsProvider), _tabCoach[index],
        stillWanted: () => _index == index);
  }

  @override
  Widget build(BuildContext context) {
    // 이전 백업을 불러올지 묻는 단계가 끝나면 홈 도움말을 띄운다
    // 홈 '최근 6개월' 그래프 · '통계 ›'를 누르면 통계 탭으로
    ref.listen(tabRequestProvider, (_, request) {
      if (request == null || request.tab == _index) return;
      setState(() => _index = request.tab);
      _showTabCoach();
    });
    ref.listen(restorePromptDoneProvider, (_, done) {
      if (done) _afterStart();
    });
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // 홈에 기록이 하나도 없을 때만 버튼 바로 위에 화살표를 띄운다
    final showArrow =
        _index == 0 && (ref.watch(homeProvider).value?.recent.isEmpty ?? false);
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButtonLocation: const RecordFabLocation(),
      floatingActionButton: keyboardOpen
          ? null
          // 메뉴가 열려 있으면 같은 자리에 X 버튼이 보이므로 숨긴다
          : Visibility.maintain(
              visible: !_menuOpen,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showArrow)
                    // 도움말이 떠 있을 때는 도움말 문구와 겹치지 않게 숨긴다
                    ValueListenableBuilder(
                      valueListenable: coachOpen,
                      builder: (_, open, child) =>
                          Opacity(opacity: open ? 0 : 1, child: child),
                      child: const IgnorePointer(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Icon(Icons.south,
                              size: 40, color: AppColors.primary),
                        ),
                      ),
                    ),
                  CoachTarget(
                    spot: CoachSpot.recordButton,
                    child: TestId(
                      'btn_record',
                      child: RecordFab(
                      onPressed: () {
                        setState(() => _menuOpen = true);
                        showRecordMenu(context, ref, onClosed: () {
                          if (mounted) setState(() => _menuOpen = false);
                        });
                      },
                    ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        onTap: (i) {
          setState(() => _index = i);
          _showTabCoach();
        },
      ),
    );
  }
}
