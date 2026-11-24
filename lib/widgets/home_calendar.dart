import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/gift_record.dart';
import '../models/upcoming_item.dart';
import '../screens/event_detail_screen.dart';
import '../screens/person_detail_screen.dart';
import '../screens/reception_summary_screen.dart';
import '../services/format.dart';
import '../theme/app_theme.dart';
import 'capped_scroll_list.dart';
import 'coach_mark.dart';
import 'collapsible_section.dart';
import 'common.dart';
import 'test_id.dart';

/// 홈 '일정' 섹션 (추가 AC): 달력(주간 띠 ↔ 월 달력) + 다가오는 일정.
/// - 제목 줄 오른쪽 '월 달력' / '주간'(글자만, 추가 AD) + 접기 화살표. 접히면 '· n개'(다가오는 일정 개수)
/// - 날짜 아래 점(최대 3개): 보냄 코랄 · 받음 파랑 · 일정/행사 회색
/// - 날짜를 누르면 아래 목록이 그날 내역으로, 같은 날을 다시 누르면 다가오는 일정으로
/// - 달력은 표시 중인 주 · 달의 데이터만 읽는다([calendarDataProvider])
class HomeScheduleSection extends ConsumerStatefulWidget {
  const HomeScheduleSection({
    super.key,
    required this.upcoming,
    this.footerBelowList,
  });

  final List<UpcomingItem> upcoming;

  /// 다가오는 일정 목록 바로 아래(알림이 꺼져 있어요 줄 등)
  final Widget? footerBelowList;

  @override
  ConsumerState<HomeScheduleSection> createState() =>
      _HomeScheduleSectionState();
}

/// 이번 주 · 이번 달이 놓이는 페이지 번호 (앞뒤로 넉넉히 밀 수 있게)
const _basePage = 10000;

/// 일요일 시작 주의 첫날
DateTime weekStartOf(DateTime d) {
  final day = dateOnly(d);
  return DateTime(day.year, day.month, day.day - day.weekday % 7);
}

/// '11월 4주': 주 가운데(목요일)가 속한 달의 몇째 주 (일요일 시작)
String weekLabel(DateTime weekStart) {
  final mid = DateTime(weekStart.year, weekStart.month, weekStart.day + 4);
  final offset = DateTime(mid.year, mid.month, 1).weekday % 7;
  return '${mid.month}월 ${(mid.day + offset - 1) ~/ 7 + 1}주';
}

class _HomeScheduleSectionState extends ConsumerState<HomeScheduleSection> {
  late final DateTime _thisWeek = weekStartOf(DateTime.now());
  late final DateTime _thisMonth =
      DateTime(DateTime.now().year, DateTime.now().month);

  int _weekPage = _basePage;
  int _monthPage = _basePage;
  PageController? _weekController;
  PageController? _monthController;

  /// 고른 날짜 (null이면 아래 목록은 다가오는 일정)
  DateTime? _selected;

  DateTime _weekAt(int page) => DateTime(
      _thisWeek.year, _thisWeek.month, _thisWeek.day + 7 * (page - _basePage));
  DateTime _monthAt(int page) =>
      DateTime(_thisMonth.year, _thisMonth.month + (page - _basePage));

  int _weekPageOf(DateTime d) {
    // 날짜 차이를 시간으로 재서 반올림한다(하루 길이가 다른 날이 있어도 어긋나지 않게)
    final days = (weekStartOf(d).difference(_thisWeek).inHours / 24).round();
    return _basePage + days ~/ 7;
  }

  int _monthPageOf(DateTime d) =>
      _basePage + (d.year - _thisMonth.year) * 12 + d.month - _thisMonth.month;

  @override
  void dispose() {
    _weekController?.dispose();
    _monthController?.dispose();
    super.dispose();
  }

  PageController _weekCtrl() =>
      _weekController ??= PageController(initialPage: _weekPage);
  PageController _monthCtrl() =>
      _monthController ??= PageController(initialPage: _monthPage);

  /// 주간 ↔ 월 달력. 고른 날(없으면 보고 있던 주 · 달)이 보이게 맞춘다.
  void _toggleMode(bool month) {
    if (month) {
      final anchor = _selected ??
          DateTime(_weekAt(_weekPage).year, _weekAt(_weekPage).month,
              _weekAt(_weekPage).day + 3);
      _monthPage = _monthPageOf(anchor);
      _monthController?.dispose();
      _monthController = null;
    } else {
      final shown = _monthAt(_monthPage);
      final anchor = _selected ??
          (shown == _thisMonth ? DateTime.now() : shown);
      _weekPage = _weekPageOf(anchor);
      _weekController?.dispose();
      _weekController = null;
    }
    ref.read(homeCalendarMonthProvider.notifier).toggle();
  }

  void _tapDay(DateTime day) => setState(
      () => _selected = _selected != null && _isSameDay(_selected!, day)
          ? null
          : day);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(homeCalendarMonthProvider);
    final count = widget.upcoming.length;
    return CollapsibleSection(
      section: HomeSection.schedules,
      title: '일정',
      coachSpot: CoachSpot.homeCollapse,
      collapsedCount: count > 0 ? '· $count개' : null,
      trailing: TestId(
        'home_calendar_mode',
        selected: month,
        child: LinkText(month ? '주간' : '월 달력',
            onTap: () => _toggleMode(!month)),
      ),
      footer: const Padding(
        padding: EdgeInsets.only(top: AppSpacing.section - 6),
        child: AppDivider(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (month) _monthView() else _weekView(),
          const _CalendarLegend(),
          const SizedBox(height: 8),
          if (_selected case final day?)
            _DayList(day: day)
          else ...[
            _UpcomingList(items: widget.upcoming),
            ?widget.footerBelowList,
          ],
        ],
      ),
    );
  }

  // ───────────── 주간 띠 ─────────────

  Widget _weekView() {
    final start = _weekAt(_weekPage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 4),
          child: TestId('home_week_label',
              child: Text(weekLabel(start), style: AppText.sub)),
        ),
        SizedBox(
          height: 78,
          child: PageView.builder(
            controller: _weekCtrl(),
            onPageChanged: (p) => setState(() => _weekPage = p),
            itemBuilder: (context, page) {
              final s = _weekAt(page);
              final e = DateTime(s.year, s.month, s.day + 6);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page - 8),
                child: _RangeDays(
                  start: s,
                  end: e,
                  builder: (data) => Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: _DayCell(
                            day: DateTime(s.year, s.month, s.day + i),
                            data: data,
                            selected: _selected,
                            showWeekday: true,
                            onTap: _tapDay,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ───────────── 월 달력 ─────────────

  Widget _monthView() {
    final shown = _monthAt(_monthPage);
    final last = DateTime(shown.year, shown.month + 1, 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page - 12),
          child: Row(
            children: [
              TestId('cal_prev', child: IconButton(
                tooltip: '이전 달',
                onPressed: () => _monthCtrl().previousPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut),
                icon: const Icon(Icons.chevron_left),
              )),
              TestId('cal_month_title', child: Text(
                  '${shown.year}년 ${shown.month}월',
                  style: AppText.sectionTitle)),
              TestId('cal_next', child: IconButton(
                tooltip: '다음 달',
                onPressed: () => _monthCtrl().nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut),
                icon: const Icon(Icons.chevron_right),
              )),
              const Spacer(),
              TestId('cal_today', child: TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => _monthCtrl().animateToPage(_basePage,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut),
                child: const Text('오늘', style: AppText.link),
              )),
            ],
          ),
        ),
        // 그달 합계 한 줄: 보냄(코랄) · 받음(파랑)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 8),
          child: _RangeDays(
            start: shown,
            end: last,
            builder: (data) => TestId('cal_month_total', child: Text.rich(
              TextSpan(style: AppText.sub, children: [
                const TextSpan(text: '보냄 '),
                TextSpan(
                    text: formatWon(data.sentTotal),
                    style: const TextStyle(
                        color: AppColors.sent, fontWeight: FontWeight.w700)),
                const TextSpan(text: ' · 받음 '),
                TextSpan(
                    text: formatWon(data.receivedTotal),
                    style: const TextStyle(
                        color: AppColors.received, fontWeight: FontWeight.w700)),
              ]),
            )),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page - 8),
          child: Row(
            children: [
              for (final (i, w) in const ['일', '월', '화', '수', '목', '금', '토'].indexed)
                Expanded(
                  child: Center(
                    child: Text(w,
                        style: AppText.sub.copyWith(
                            fontSize: 12,
                            color: i == 0 ? AppColors.sent : AppColors.textSub)),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 6 * 52,
          child: PageView.builder(
            controller: _monthCtrl(),
            onPageChanged: (p) => setState(() => _monthPage = p),
            itemBuilder: (context, page) {
              final m = _monthAt(page);
              final mLast = DateTime(m.year, m.month + 1, 0);
              final gridStart = weekStartOf(m);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page - 8),
                child: _RangeDays(
                  start: m,
                  end: mLast,
                  builder: (data) => Column(
                    children: [
                      for (var w = 0; w < 6; w++)
                        SizedBox(
                          height: 52,
                          child: Row(
                            children: [
                              for (var i = 0; i < 7; i++)
                                Expanded(
                                  child: Builder(builder: (_) {
                                    final day = DateTime(gridStart.year,
                                        gridStart.month, gridStart.day + w * 7 + i);
                                    final inMonth = day.month == m.month;
                                    return _DayCell(
                                      day: day,
                                      data: inMonth ? data : CalendarData.empty,
                                      selected: _selected,
                                      faded: !inMonth,
                                      onTap: _tapDay,
                                    );
                                  }),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// [start] ~ [end]의 달력 데이터를 읽어 그린다. 읽는 중 · 오류면 점 없이 그린다.
class _RangeDays extends ConsumerWidget {
  const _RangeDays({
    required this.start,
    required this.end,
    required this.builder,
  });
  final DateTime start;
  final DateTime end;
  final Widget Function(CalendarData data) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref
            .watch(calendarDataProvider((start: start, end: end)))
            .value ??
        CalendarData.empty;
    return builder(data);
  }
}

/// 날짜 한 칸: (요일) 숫자 + 아래 점 최대 3개. 오늘은 파란 동그라미, 고른 날은 연한 파란 바탕.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.data,
    required this.selected,
    required this.onTap,
    this.showWeekday = false,
    this.faded = false,
  });
  final DateTime day;
  final CalendarData data;
  final DateTime? selected;
  final ValueChanged<DateTime> onTap;
  final bool showWeekday;
  final bool faded;

  static const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final isToday = dateOnly(day) == today;
    final isSelected = selected != null && dateOnly(selected!) == dateOnly(day);
    final dots = [
      if (data.sentOn(day)) AppColors.sent,
      if (data.receivedOn(day)) AppColors.received,
      if (data.itemsOn(day).isNotEmpty) AppColors.calendarDot,
    ];
    final key = '${day.year}${'${day.month}'.padLeft(2, '0')}${'${day.day}'.padLeft(2, '0')}';
    return TestId(
      'cal_day_$key',
      selected: isSelected,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onTap(day),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primarySoft : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showWeekday) ...[
                Text(_weekdays[day.weekday % 7],
                    style: AppText.sub.copyWith(
                        fontSize: 12,
                        color: day.weekday == DateTime.sunday
                            ? AppColors.sent
                            : AppColors.textSub)),
                const SizedBox(height: 2),
              ],
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: isToday
                    ? const BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle)
                    : null,
                child: Text(
                  '${day.day}',
                  style: AppText.body.copyWith(
                    fontSize: 14,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    color: isToday
                        ? AppColors.background
                        : (faded ? AppColors.textHint : AppColors.text),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in dots)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration:
                            BoxDecoration(color: c, shape: BoxShape.circle),
                      ),
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

/// 범례: ● 보냄 ● 받음 ● 일정/행사
class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String t) => Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(t, style: AppText.sub.copyWith(fontSize: 12)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          dot(AppColors.sent, '보냄'),
          dot(AppColors.received, '받음'),
          dot(AppColors.calendarDot, '일정/행사'),
        ],
      ),
    );
  }
}

/// 라벨 칩: '일정' 회색 · '내 행사' 파랑 · '다른 사람 행사' 회색 · '받음' 파랑 · '보냄' 코랄
class _LabelChip extends StatelessWidget {
  const _LabelChip(this.text, {this.color, this.background});
  final String text;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: background ?? AppColors.divider,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color ?? AppColors.textSub)),
      );

  factory _LabelChip.kind(UpcomingKind kind) => kind == UpcomingKind.myEvent
      ? _LabelChip(kind.label,
          color: AppColors.primary, background: AppColors.primarySoft)
      : _LabelChip(kind.label);
}

void _openItem(BuildContext context, UpcomingItem item) {
  final Widget screen = item.reception != null
      ? ReceptionSummaryScreen(receptionId: item.reception!.id)
      : EventDetailScreen(eventId: item.event!.id!);
  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
}

/// 일정 · 행사 줄 앞의 날짜 표시 자리 (다가오는 일정 · 날짜 목록 공통 너비)
const _dDayWidth = 56.0;

/// 날짜 목록의 D±n 색: 지난 날 회색, 오늘 · 앞으로 파랑
Color _dDayColor(DateTime date) =>
    daysFromToday(date) < 0 ? AppColors.textSub : AppColors.primary;

/// 다가오는 일정 한 줄: D-n + 이름(+알림 종) + 라벨 칩 + 날짜
class UpcomingTile extends StatelessWidget {
  const UpcomingTile({super.key, required this.item, this.highlight = false});
  final UpcomingItem item;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return TestId(
      'upcoming_item_${item.title}',
      child: InkWell(
        onTap: () => _openItem(context, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.page, vertical: AppSpacing.item),
          child: Row(
            children: [
              SizedBox(
                width: _dDayWidth,
                child: Text(dDayLabel(item.date),
                    style: AppText.dDay.copyWith(
                        color: highlight ? AppColors.primary : AppColors.icon)),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(item.title,
                            style: AppText.listName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (item.hasReminder) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.notifications_none,
                            key: ValueKey('upcoming_bell'),
                            size: 15,
                            color: AppColors.textSub),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Row(children: [
                      _LabelChip.kind(item.kind),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(formatDate(item.date),
                            style: AppText.sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.divider),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpcomingList extends StatelessWidget {
  const _UpcomingList({required this.items});
  final List<UpcomingItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const TestId(
        'home_no_schedule',
        child: EmptyView(
          icon: Icons.event_available,
          message: '다가오는 일정이 없어요.',
        ),
      );
    }
    // 추가 AA: 전부 넣고 약 4.5줄 높이까지만 보이며 안에서 스크롤
    return CappedScrollList(
      itemCount: items.length,
      itemBuilder: (context, i) =>
          UpcomingTile(item: items[i], highlight: i == 0),
    );
  }
}

/// 고른 날짜의 내역: 받음(+파랑) · 보냄(−코랄) · 일정 · 행사. 없으면 "이 날은 기록이 없어요".
class _DayList extends ConsumerWidget {
  const _DayList({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dateOnly(day);
    final data =
        ref.watch(calendarDataProvider((start: d, end: d))).value ??
            CalendarData.empty;
    final records = data.recordsOn(d);
    final received = records.where((r) => !r.isSent).toList();
    final sent = records.where((r) => r.isSent).toList();
    final items = data.itemsOn(d);
    final rows = <Widget>[
      for (final r in received) _recordRow(context, r),
      for (final r in sent) _recordRow(context, r),
      for (final u in items) _itemRow(context, u),
    ];
    return TestId(
      'cal_day_list',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 4, AppSpacing.page, 4),
            child: Text(formatShortDateWithDay(d), style: AppText.sectionTitle),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.page, vertical: 16),
              child: Text('이 날은 기록이 없어요', style: AppText.sub),
            )
          else
            CappedScrollList(
              itemCount: rows.length,
              itemBuilder: (_, i) => rows[i],
            ),
        ],
      ),
    );
  }

  /// 보냄 · 받음 줄: 이름 + 칩 … 금액(오른쪽 끝) + ›. 누르면 그 사람 상세(기록 목록 · 수정)
  Widget _recordRow(BuildContext context, GiftRecord r) => TestId(
        'cal_record_${r.id}',
        child: InkWell(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => PersonDetailScreen(personId: r.personId))),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.page, vertical: AppSpacing.item),
            child: Row(
              children: [
                // 이름 · 칩이 남는 자리를 모두 차지해 금액이 오른쪽 끝에 붙는다
                Expanded(
                  child: Row(children: [
                    Flexible(
                      child: Text(r.personName ?? '',
                          style: AppText.listName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    r.isSent
                        ? const _LabelChip('보냄',
                            color: AppColors.sent,
                            background: AppColors.sentSoft)
                        : const _LabelChip('받음',
                            color: AppColors.received,
                            background: AppColors.primarySoft),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(signedWon(r.amount, isSent: r.isSent),
                    style: AppText.listAmount
                        .copyWith(color: AppColors.amount(r.isSent))),
                const Icon(Icons.chevron_right, color: AppColors.divider),
              ],
            ),
          ),
        ),
      );

  /// 일정 · 내 행사 · 다른 사람 행사 줄: D±n(다가오는 일정과 같은 자리 · 크기) + 이름 + 칩 + ›.
  /// 지난 날짜의 행사도 눌러서 상세로 들어간다.
  Widget _itemRow(BuildContext context, UpcomingItem u) => TestId(
        'cal_item_${u.title}',
        child: InkWell(
          onTap: () => _openItem(context, u),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.page, vertical: AppSpacing.item),
            child: Row(
              children: [
                SizedBox(
                  width: _dDayWidth,
                  child: Text(dDayLabel(u.date),
                      style: AppText.dDay.copyWith(color: _dDayColor(u.date))),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Row(children: [
                    Flexible(
                      child: Text(u.title,
                          style: AppText.listName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    _LabelChip.kind(u.kind),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: AppColors.divider),
              ],
            ),
          ),
        ),
      );
}
