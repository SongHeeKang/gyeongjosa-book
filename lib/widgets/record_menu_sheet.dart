import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/event.dart';
import '../screens/event_form_screen.dart';
import '../screens/quick_entry_screen.dart';
import '../screens/reception_form_screen.dart';
import '../services/format.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import 'coach_mark.dart';
import 'common.dart';
import 'person_picker_sheet.dart';
import 'screen_coach.dart';

enum _RecordAction { sent, schedule, received, reception }

/// 기록하기 메뉴: 연필 버튼 위로 카드 4개가 펼쳐지고, 고르면 해당 화면으로 간다.
/// [onClosed]는 메뉴가 닫힐 때(화면 이동 전에) 불린다.
Future<void> showRecordMenu(BuildContext context, WidgetRef ref,
    {VoidCallback? onClosed}) async {
  final buttonRect = CoachTarget.rectOf(CoachSpot.recordButton);
  final action = await Navigator.of(context, rootNavigator: true)
      .push(PageRouteBuilder<_RecordAction>(
    opaque: false,
    barrierDismissible: true,
    barrierLabel: '닫기',
    barrierColor: AppColors.menuScrim,
    transitionDuration: _menuDuration,
    reverseTransitionDuration: _menuDuration,
    pageBuilder: (_, animation, _) =>
        _RecordMenu(animation: animation, buttonRect: buttonRect),
  ));
  onClosed?.call();
  if (action == null || !context.mounted) return;
  switch (action) {
    case _RecordAction.sent:
      await startSentRecord(context, ref);
    case _RecordAction.schedule:
      await Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => const EventFormScreen()));
    case _RecordAction.received:
      await _startReceivedEntry(context, ref);
    case _RecordAction.reception:
      await Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => const ReceptionFormScreen()));
  }
}

/// [받은 명단 직접 입력]: 내 행사를 고르고(없으면 바로 만들고) 연속 입력으로 간다.
Future<void> _startReceivedEntry(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  final mine = await repo.myEvents();
  if (!context.mounted) return;

  Event? event;
  var createNew = mine.isEmpty;
  if (mine.length == 1) event = mine.first;
  if (mine.length > 1) {
    final picked = await showModalBottomSheet<_EventPick>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _MyEventPickerSheet(events: mine),
    );
    if (picked == null || !context.mounted) return;
    event = picked.event;
    createNew = picked.event == null;
  }
  if (createNew) {
    final id = await Navigator.push<int>(
        context,
        MaterialPageRoute<int>(
            builder: (_) => const EventFormScreen(initialIsMine: true)));
    if (id == null) return;
    event = await repo.getEvent(id);
    if (!context.mounted) return;
  }
  final target = event;
  if (target == null) return;
  await Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => QuickEntryScreen(event: target)));
}

class _EventPick {
  final Event? event; // null이면 새로 만들기
  const _EventPick(this.event);
}

const _menuDuration = Duration(milliseconds: 200);

class _RecordMenu extends ConsumerStatefulWidget {
  const _RecordMenu({required this.animation, required this.buttonRect});
  final Animation<double> animation;

  /// 기록하기 버튼 자리. X 버튼을 같은 자리에 놓는다.
  final Rect? buttonRect;

  @override
  ConsumerState<_RecordMenu> createState() => _RecordMenuState();
}

class _RecordMenuState extends ConsumerState<_RecordMenu> {
  /// 열리면 연필이 돌며 X로, 닫히기 시작하면 다시 연필로 바뀐다.
  bool _open = false;

  static const _cardWidth = 280.0;
  static const _cardHeight = 60.0;
  static const _cardGap = 10.0;
  static const _stagger = 40.0 / 200.0; // 한 장씩 40ms 차이

  static const _cards = [
    (
      _RecordAction.sent,
      CoachSpot.menuSent,
      Icons.card_giftcard,
      '보냈어요',
      '축의금·부의금을 냈어요',
      AppColors.menuSent,
      AppColors.menuSentSoft,
    ),
    (
      _RecordAction.schedule,
      CoachSpot.menuSchedule,
      Icons.event_outlined,
      '일정 추가',
      '청첩장·부고를 받았어요',
      AppColors.menuSchedule,
      AppColors.menuScheduleSoft,
    ),
    (
      _RecordAction.received,
      CoachSpot.menuDirect,
      Icons.playlist_add,
      '받은 명단 직접 입력',
      '종이 장부·계좌이체를 옮겨 적어요',
      AppColors.menuDirect,
      AppColors.menuDirectSoft,
    ),
    (
      _RecordAction.reception,
      CoachSpot.menuReception,
      Icons.assignment_outlined,
      '행사장 접수',
      '접수대에서 바로 받아요',
      AppColors.menuReception,
      AppColors.menuReceptionSoft,
    ),
  ];

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onAnimationStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _open = true);
      showCoachOnce(context, ref.read(prefsProvider), CoachScreen.recordMenu);
    });
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse && mounted) {
      setState(() => _open = false);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onAnimationStatus);
    super.dispose();
  }

  /// 버튼에 가까운 아래 카드부터 차례로 올라온다. 닫을 때는 그 반대.
  Widget _appear(int index, Widget child) {
    final fromBottom = _cards.length - 1 - index;
    final start = (fromBottom * _stagger).clamp(0.0, 0.6);
    final progress = CurvedAnimation(
      parent: widget.animation,
      curve: Interval(start, (start + 0.4).clamp(0.0, 1.0), curve: Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (_, child) => Opacity(
        opacity: progress.value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - progress.value)),
          child: child,
        ),
      ),
    );
  }

  Widget _card(
      (_RecordAction, CoachSpot, IconData, String, String, Color, Color) c) {
    final (action, spot, icon, title, sub, color, soft) = c;
    final testId = switch (action) {
      _RecordAction.sent => 'menu_sent',
      _RecordAction.schedule => 'menu_schedule',
      _RecordAction.received => 'menu_received',
      _RecordAction.reception => 'menu_reception',
    };
    return TestId(testId, child: CoachTarget(
      spot: spot,
      // 글자를 크게 키운 폰에서는 카드가 아래로 늘어나 글자가 잘리지 않게 한다
      child: Container(
        width: _cardWidth,
        constraints: const BoxConstraints(minHeight: _cardHeight),
        child: Material(
          color: AppColors.background,
          elevation: 2,
          shadowColor: AppColors.menuScrim,
          borderRadius: BorderRadius.circular(30),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).pop(action),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 10, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: AppText.menuTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(sub,
                            style: AppText.sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: soft, borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, size: 22, color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 기록하기 버튼의 오른쪽 아래를 기준으로 같은 자리에 놓는다.
    final rect = widget.buttonRect;
    final right =
        rect == null ? AppSpacing.page : media.size.width - rect.right;
    final bottom = rect == null
        ? media.padding.bottom + 96
        : media.size.height - rect.bottom;
    return Stack(
      children: [
        Positioned(
          right: right,
          bottom: bottom + RecordFab.size + 14,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _cards.length; i++) ...[
                if (i > 0) const SizedBox(height: _cardGap),
                _appear(i, _card(_cards[i])),
              ],
            ],
          ),
        ),
        Positioned(
          right: right,
          bottom: bottom,
          child: CoachTarget(
            spot: CoachSpot.menuClose,
            child: TestId('menu_close', child: RecordFab(
              icon: _open ? Icons.close : Icons.edit_outlined,
              tooltip: _open ? '닫기' : '기록하기',
              onPressed: () => Navigator.of(context).pop(),
            )),
          ),
        ),
      ],
    );
  }
}

class _MyEventPickerSheet extends StatelessWidget {
  const _MyEventPickerSheet({required this.events});
  final List<Event> events;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding:
                EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 12),
            child: Text('어느 행사의 명단인가요?', style: AppText.appTitle),
          ),
          for (final e in events)
            ListTile(
              title: Text(e.title),
              subtitle: Text(formatDate(e.date)),
              onTap: () => Navigator.pop(context, _EventPick(e)),
            ),
          ListTile(
            leading: const Icon(Icons.add, color: AppColors.primary),
            title: Text('새 내 행사 만들기',
                style: AppText.listName.copyWith(color: AppColors.primary)),
            onTap: () => Navigator.pop(context, const _EventPick(null)),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
