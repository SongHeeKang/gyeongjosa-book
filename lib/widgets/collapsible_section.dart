import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'coach_mark.dart';
import 'test_id.dart';

/// 홈에서 접고 펼 수 있는 섹션
enum HomeSection {
  schedules('home_schedules'),
  months('home_months'),
  records('home_records');

  const HomeSection(this.id);

  /// 저장 이름 · 자동화 테스트 식별자에 쓴다
  final String id;
}

/// 홈 섹션의 접힘 상태. 기본은 모두 펼침이고, 바꾼 상태는 shared_preferences에 남아
/// 앱을 다시 켜도 그대로다. 안드로이드 '데이터 삭제'로 설정이 지워지면 다시 모두 펼침.
class HomeCollapsed extends Notifier<Set<HomeSection>> {
  @override
  Set<HomeSection> build() {
    final prefs = ref.watch(prefsProvider);
    return {
      for (final s in HomeSection.values)
        if (prefs.getBool(PrefKeys.homeCollapsed(s.id)) ?? false) s,
    };
  }

  void toggle(HomeSection section) {
    final collapsed = !state.contains(section);
    state = collapsed ? {...state, section} : ({...state}..remove(section));
    ref
        .read(prefsProvider)
        .setBool(PrefKeys.homeCollapsed(section.id), collapsed);
  }
}

final homeCollapsedProvider = NotifierProvider<HomeCollapsed, Set<HomeSection>>(
  HomeCollapsed.new,
);

/// 접기 · 펼치기 섹션: 제목 줄(제목 · 접혔을 때 개수 · 링크 · 화살표) + 내용.
/// 화살표나 제목을 누르면 접히고 펴진다(높이 애니메이션 + 화살표 회전 200ms).
/// [trailing] 링크('전체 보기' · '통계 ›')는 화살표 왼쪽에 두고 눌러도 접히지 않는다.
/// 링크가 없어도 화살표 자리는 같다. 새 기록이 생겨도 저절로 펼치지 않는다.
class CollapsibleSection extends ConsumerWidget {
  const CollapsibleSection({
    super.key,
    required this.section,
    required this.title,
    required this.child,
    this.trailing,
    this.collapsedCount,
    this.footer,
    this.coachSpot,
  });

  /// 화면별 도움말이 화살표를 가리킬 자리
  final CoachSpot? coachSpot;

  final HomeSection section;
  final String title;
  final Widget child;
  final Widget? trailing;

  /// 접혔을 때 제목 옆 회색 글자(예: '· 2개'). null이면 표시하지 않는다.
  final String? collapsedCount;

  /// 접혀도 늘 보이는 아래쪽(섹션 사이 구분선 등)
  final Widget? footer;

  static const duration = Duration(milliseconds: 200);

  Widget _coach(Widget child) =>
      coachSpot == null ? child : CoachTarget(spot: coachSpot!, child: child);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(homeCollapsedProvider).contains(section);
    void toggle() => ref.read(homeCollapsedProvider.notifier).toggle(section);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.section,
            AppSpacing.page - 16,
            6,
          ),
          child: Row(
            children: [
              Expanded(
                child: TestId(
                  '${section.id}_title',
                  child: InkWell(
                    onTap: toggle,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(title, style: AppText.sectionTitle),
                          ),
                          if (collapsed && collapsedCount != null) ...[
                            const SizedBox(width: 6),
                            Text(collapsedCount!, style: AppText.sub),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ?trailing,
              _coach(
                TestId(
                  '${section.id}_toggle',
                  selected: !collapsed,
                  child: IconButton(
                    tooltip: collapsed ? '$title 펼치기' : '$title 접기',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: toggle,
                    icon: AnimatedRotation(
                      // 펼침 = 위쪽 ⌃, 접힘 = 아래쪽 ⌄
                      turns: collapsed ? 0.5 : 0,
                      duration: duration,
                      child: const Icon(
                        Icons.keyboard_arrow_up,
                        color: AppColors.textSub,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: duration,
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: collapsed ? const SizedBox(width: double.infinity) : child,
          ),
        ),
        ?footer,
      ],
    );
  }
}
