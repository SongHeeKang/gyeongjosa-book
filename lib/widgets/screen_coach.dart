import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import 'coach_mark.dart';

/// 화면별 도움말 내용. [auto]면 그 화면에 처음 들어갈 때 한 번 자동으로 보여준다.
enum CoachScreen {
  home('홈', [
    CoachMark(CoachSpot.recordButton, '모든 기록은 여기서 시작해요'),
    CoachMark(CoachSpot.homePending, '다녀온 행사는 금액만 누르면 기록돼요'),
    CoachMark(CoachSpot.homeHelp, '이 도움말은 여기서 다시 볼 수 있어요'),
  ]),
  recordMenu(
      '기록하기 메뉴',
      [
        // 카드마다 설명이 적혀 있으니 하나로 묶어 설명도 하나만 둔다.
        CoachMark(
          CoachSpot.menuSent,
          '하고 싶은 일을 골라요\n카드마다 무엇을 하는지 적혀 있어요',
          also: [CoachSpot.menuSchedule, CoachSpot.menuReceive],
        ),
      ],
      reveal: CoachReveal(CoachSpot.menuClose, '닫기')),
  people('사람', [
    CoachMark(CoachSpot.peopleSearch, '이름으로 찾아요'),
    CoachMark(CoachSpot.peopleCard, '주고받은 합계가 한눈에. 누르면 전체 기록'),
  ]),
  myEvents(
      '내 행사',
      [
        CoachMark(CoachSpot.myEventsCreate, '결혼식·돌잔치처럼 내가 받는 행사를 만들어요'),
        CoachMark(CoachSpot.myEventsFirst, '누르면 받은 명단과 받은 돈 적기 버튼이 나와요'),
      ],
      auto: false),
  eventDetail('내 행사 상세', [
    CoachMark(CoachSpot.eventReceive, '당일 접수대에서도, 끝난 뒤 종이 장부를 옮길 때도 여기서'),
    CoachMark(CoachSpot.eventImport, '대신 받아 준 사람이 보낸 장부 파일을 합쳐요'),
    CoachMark(CoachSpot.eventSend, '가족에게 명단을 보내요'),
  ]),
  stats('통계', [
    CoachMark(CoachSpot.statsPeriod, '연도를 바꿔 봐요'),
    CoachMark(CoachSpot.statsChart, '보낸 돈과 받은 돈을 비교해요'),
  ]),
  // 내 행사 · 대신 받기 모두 첫 저장 전에만 자동으로 띄운다 (화면에서 직접 부른다).
  receiveMoney('받은 돈 적기', [
    CoachMark(CoachSpot.receiveAmounts, '이름을 적고 금액을 누르면 바로 저장'),
    CoachMark(CoachSpot.receiveRecent, '방금 저장한 손님이 맨 위에'),
    CoachMark(CoachSpot.receivePlace, '여기에 저장돼요(내 행사 / 대신 받기)'),
  ]),
  quickEntry('빠른 연속 입력', [
    CoachMark(CoachSpot.quickAmounts, '이름 쓰고 금액을 누르면 저장, 바로 다음 사람'),
    CoachMark(CoachSpot.quickList, '적은 명단이 쌓여요. 누르면 수정'),
  ]);

  const CoachScreen(this.title, this.marks, {this.auto = true, this.reveal});
  final String title;

  /// 한 화면에 최대 3개
  final List<CoachMark> marks;
  final bool auto;
  final CoachReveal? reveal;

  String get _prefKey => 'coach_seen_$name';
}

List<CoachMark> _visibleMarks(CoachScreen screen) => [
      for (final m in screen.marks)
        if (m.rect != null) m,
    ];

/// 지금 화면에 있는 자리만 골라 도움말을 보여준다. 보여줄 것이 없으면 false.
Future<bool> showCoach(BuildContext context, CoachScreen screen) async {
  final marks = _visibleMarks(screen);
  if (marks.isEmpty) return false;
  await showCoachOverlay(context, marks, reveal: screen.reveal);
  return true;
}

/// 그 화면에서 처음이면 한 번 보여준다. 첫 실행 안내가 끝나기 전이나,
/// 다른 창이 위에 떠 있으면 보여주지 않고 다음 기회로 넘긴다. 보여줬으면 true.
Future<bool> showCoachOnce(
  BuildContext context,
  SharedPreferences prefs,
  CoachScreen screen, {
  bool Function()? stillWanted,
}) async {
  bool seen() => prefs.getBool(screen._prefKey) ?? false;
  bool ready() => prefs.getBool(PrefKeys.restorePromptDone) ?? false;
  if (!screen.auto || seen() || !ready()) return false;
  // 화면과 데이터가 자리 잡기를 잠깐 기다린다.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (!context.mounted || seen()) return false;
  if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
  if (stillWanted != null && !stillWanted()) return false;
  if (_visibleMarks(screen).isEmpty) return false;
  await prefs.setBool(screen._prefKey, true);
  if (!context.mounted) return false;
  return showCoach(context, screen);
}

/// '도움말 처음부터 다시 보기': 각 화면에 들어가면 다시 자동으로 보인다.
Future<void> resetCoachMarks(SharedPreferences prefs) async {
  for (final screen in CoachScreen.values) {
    await prefs.remove(screen._prefKey);
  }
}

/// 설정 아이콘 왼쪽의 (?) 버튼
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.screen, this.onClosed, this.size});
  final CoachScreen screen;

  /// 도움말을 닫은 뒤 (커서 되돌리기 등)
  final VoidCallback? onClosed;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: TestId(
        'btn_help',
        child: IconButton(
        tooltip: '도움말',
        iconSize: size,
        constraints: size == null
            ? null
            : const BoxConstraints(minWidth: 36, minHeight: 44),
        padding: size == null ? null : EdgeInsets.zero,
        color: AppColors.icon,
        icon: const Icon(Icons.help_outline),
        onPressed: () async {
          await showCoach(context, screen);
          onClosed?.call();
        },
      ),
      ),
    );
  }
}

/// 이 위젯이 화면에 나타나면 그 화면의 도움말을 처음 한 번 띄운다. 자리는 차지하지 않는다.
class AutoCoach extends StatefulWidget {
  const AutoCoach({super.key, required this.prefs, required this.screen, this.onClosed});
  final SharedPreferences prefs;
  final CoachScreen screen;
  final VoidCallback? onClosed;

  @override
  State<AutoCoach> createState() => _AutoCoachState();
}

class _AutoCoachState extends State<AutoCoach> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final shown =
          await showCoachOnce(context, widget.prefs, widget.screen);
      if (shown) widget.onClosed?.call();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
