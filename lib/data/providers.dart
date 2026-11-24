import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/event.dart';
import '../models/gift_record.dart';
import '../models/person.dart';
import '../models/reception.dart';
import '../models/upcoming_item.dart';
import '../services/format.dart';
import '../services/settings_service.dart';
import 'database_helper.dart';
import 'repository.dart';

final repositoryProvider =
    Provider<Repository>((ref) => Repository(DatabaseHelper.instance));

final receptionSummariesProvider = FutureProvider<List<ReceptionSummary>>((ref) {
  ref.watch(dbVersionProvider);
  return ref.watch(repositoryProvider).receptionSummaries();
});

final receptionPackageProvider =
    FutureProvider.family<ReceptionPackage?, String>((ref, id) {
  ref.watch(dbVersionProvider);
  return ref.watch(repositoryProvider).getReceptionPackage(id);
});

/// DB가 바뀔 때마다 숫자를 올려서, 이 값을 보고 있는 화면들이 새로 고쳐지게 한다.
class DbVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final dbVersionProvider = NotifierProvider<DbVersion, int>(DbVersion.new);

extension DbRefresh on WidgetRef {
  /// 저장/수정/삭제 후 호출하면 관련 화면이 모두 새로 고쳐진다.
  void refreshData() => read(dbVersionProvider.notifier).bump();
}

/// 테스트 메뉴의 '더미데이터 추가' 스위치 상태
final hasDummyDataProvider = FutureProvider<bool>((ref) {
  ref.watch(dbVersionProvider);
  return ref.watch(repositoryProvider).hasDummyData();
});

final peopleSummariesProvider = FutureProvider<List<PersonSummary>>((ref) {
  ref.watch(dbVersionProvider);
  return ref.watch(repositoryProvider).peopleSummaries();
});

final allPeopleProvider = FutureProvider<List<Person>>((ref) {
  ref.watch(dbVersionProvider);
  return ref.watch(repositoryProvider).allPeople();
});

class PersonDetail {
  final Person person;
  final List<GiftRecord> records;
  const PersonDetail(this.person, this.records);

  int get sentTotal =>
      records.where((r) => r.isSent).fold(0, (s, r) => s + r.amount);
  int get receivedTotal =>
      records.where((r) => !r.isSent).fold(0, (s, r) => s + r.amount);
}

final personDetailProvider =
    FutureProvider.family<PersonDetail?, int>((ref, id) async {
  ref.watch(dbVersionProvider);
  final repo = ref.watch(repositoryProvider);
  final person = await repo.getPerson(id);
  if (person == null) return null;
  return PersonDetail(person, await repo.recordsForPerson(id));
});

final eventSummariesProvider = FutureProvider<List<EventSummary>>((ref) {
  ref.watch(dbVersionProvider);
  return ref.watch(repositoryProvider).eventSummaries();
});

class EventDetail {
  final Event event;
  final List<GiftRecord> records;
  const EventDetail(this.event, this.records);

  /// 내 행사면 받은 내역, 남의 행사면 보낸 내역만 집계
  List<GiftRecord> get mainRecords => records
      .where((r) => event.isMine ? !r.isSent : r.isSent)
      .toList();
  int get total => mainRecords.fold(0, (s, r) => s + r.amount);
}

final eventDetailProvider =
    FutureProvider.family<EventDetail?, int>((ref, id) async {
  ref.watch(dbVersionProvider);
  final repo = ref.watch(repositoryProvider);
  final event = await repo.getEvent(id);
  if (event == null) return null;
  return EventDetail(event, await repo.recordsForEvent(id));
});

class HomeData {
  final int sent;
  final int received;
  final int sentCount;
  final int receivedCount;
  /// 다가오는 일정: 일정 추가로 등록한 일정 + 내 행사 + 다른 사람 행사 (오늘 포함, 날짜순, 추가 AC)
  final List<UpcomingItem> upcoming;

  /// 다가오는 일정 전체 개수 (홈 섹션을 접었을 때 '· n개')
  final int upcomingCount;

  /// '얼마 내셨어요?' 카드에 보여줄 일정
  final List<Event> pending;

  /// 남의 행사(일정) 전체 개수. 0이면 일정 섹션을 숨긴다.
  final int scheduleCount;
  final List<GiftRecord> recent;
  final int recordCount;
  const HomeData({
    required this.sent,
    required this.received,
    required this.sentCount,
    required this.receivedCount,
    required this.upcoming,
    this.upcomingCount = 0,
    required this.pending,
    required this.scheduleCount,
    required this.recent,
    required this.recordCount,
  });

  /// 알림을 켜 둔 다가오는 일정이 있는지 (홈 '알림이 꺼져 있어요' 줄은 이때만)
  bool get hasUpcomingReminder => upcoming.any((u) => u.hasReminder);
}

final homeProvider = FutureProvider<HomeData>((ref) async {
  ref.watch(dbVersionProvider);
  final repo = ref.watch(repositoryProvider);
  final totals = await repo.yearTotals(DateTime.now().year);
  // 추가 AA: 홈 목록은 개수 제한 없이 전부(화면에서는 약 4.5줄 높이로 잘라 안에서 스크롤)
  // 추가 AC: 일정 + 다가오는 내 행사 + 다가오는 다른 사람 행사
  final today = dateOnly(DateTime.now());
  final upcoming = [
    for (final e in await repo.upcomingSchedules()) UpcomingItem.fromEvent(e),
    for (final e in await repo.upcomingMyEvents()) UpcomingItem.fromEvent(e),
    for (final r in await repo.receptionsBetween(today, null))
      UpcomingItem.fromReception(r),
  ]..sort(UpcomingItem.compare);
  return HomeData(
    sent: totals.sent,
    received: totals.received,
    sentCount: totals.sentCount,
    receivedCount: totals.receivedCount,
    upcoming: upcoming,
    upcomingCount: upcoming.length,
    pending: await repo.pendingAmountEvents(limit: 3),
    scheduleCount: await repo.countSchedules(),
    recent: await repo.recentRecords(-1), // -1: 개수 제한 없음(SQLite LIMIT -1)
    recordCount: await repo.countRecords(),
  );
});

final recordYearsProvider = FutureProvider<List<int>>((ref) {
  ref.watch(dbVersionProvider);
  return ref.watch(repositoryProvider).recordYears();
});

final monthlyTotalsProvider =
    FutureProvider.family<List<({int month, int sent, int received})>, int>(
        (ref, year) {
  ref.watch(dbVersionProvider);
  return ref.watch(repositoryProvider).monthlyTotals(year);
});

/// 홈 '최근 6개월': 이번 달을 포함한 6개월(오래된 달 → 이번 달)의 보냄 / 받음 합계
final recentMonthsProvider = FutureProvider<
    List<({int year, int month, int sent, int received})>>((ref) async {
  ref.watch(dbVersionProvider);
  final repo = ref.watch(repositoryProvider);
  final now = DateTime.now();
  final byYear = <int, List<({int month, int sent, int received})>>{};
  return [
    for (var i = 5; i >= 0; i--)
      await () async {
        final d = DateTime(now.year, now.month - i);
        final rows = byYear[d.year] ??= await repo.monthlyTotals(d.year);
        final r = rows.where((x) => x.month == d.month).firstOrNull;
        return (
          year: d.year,
          month: d.month,
          sent: r?.sent ?? 0,
          received: r?.received ?? 0,
        );
      }(),
  ];
});

/// 다른 화면에서 하단 탭을 바꿔 달라고 할 때 (홈 '최근 6개월' → 통계 탭).
/// MainShell이 듣고 탭을 바꾼다. 같은 탭을 다시 요청해도 알리도록 번호를 함께 둔다.
class TabRequest extends Notifier<({int tab, int seq})?> {
  @override
  ({int tab, int seq})? build() => null;

  void go(int tab) => state = (tab: tab, seq: (state?.seq ?? 0) + 1);
}

final tabRequestProvider =
    NotifierProvider<TabRequest, ({int tab, int seq})?>(TabRequest.new);

/// 하단 탭 번호
abstract final class AppTabs {
  static const home = 0;
  static const people = 1;
  static const events = 2;
  static const stats = 3;
}

/// 홈 달력(추가 AC): 표시 중인 주 · 달(또는 고른 하루) [start] ~ [end]의 기록과 일정 · 행사.
/// 기록 · 일정 · 행사가 바뀌면(dbVersion) 다시 읽는다.
class CalendarData {
  const CalendarData({required this.records, required this.items});

  /// 날짜(dayKey)별 보냄 · 받음 기록. 다른 사람 행사의 손님 금액은 내 돈이 아니라 넣지 않는다.
  final Map<int, List<GiftRecord>> records;

  /// 날짜별 일정 · 내 행사 · 다른 사람 행사
  final Map<int, List<UpcomingItem>> items;

  static int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  List<GiftRecord> recordsOn(DateTime d) => records[dayKey(d)] ?? const [];
  List<UpcomingItem> itemsOn(DateTime d) => items[dayKey(d)] ?? const [];

  bool sentOn(DateTime d) => recordsOn(d).any((r) => r.isSent);
  bool receivedOn(DateTime d) => recordsOn(d).any((r) => !r.isSent);

  int get sentTotal => [
        for (final l in records.values)
          for (final r in l)
            if (r.isSent) r.amount,
      ].fold(0, (a, b) => a + b);
  int get receivedTotal => [
        for (final l in records.values)
          for (final r in l)
            if (!r.isSent) r.amount,
      ].fold(0, (a, b) => a + b);

  static const empty = CalendarData(records: {}, items: {});
}

final calendarDataProvider = FutureProvider.family<CalendarData,
    ({DateTime start, DateTime end})>((ref, range) async {
  ref.watch(dbVersionProvider);
  final repo = ref.watch(repositoryProvider);
  final records = <int, List<GiftRecord>>{};
  for (final r in await repo.recordsBetween(range.start, range.end)) {
    (records[CalendarData.dayKey(r.date)] ??= []).add(r);
  }
  final items = <int, List<UpcomingItem>>{};
  for (final e in await repo.eventsBetween(range.start, range.end)) {
    (items[CalendarData.dayKey(e.date)] ??= []).add(UpcomingItem.fromEvent(e));
  }
  for (final r in await repo.receptionsBetween(range.start, range.end)) {
    (items[CalendarData.dayKey(r.date)] ??= [])
        .add(UpcomingItem.fromReception(r));
  }
  for (final l in items.values) {
    l.sort(UpcomingItem.compare);
  }
  return CalendarData(records: records, items: items);
});

/// 홈 '일정' 달력 모양: false = 주간 띠(기본), true = 월 달력. 앱을 다시 켜도 마지막 모양.
/// 안드로이드 '데이터 삭제'로 설정이 지워지면 다시 주간.
class HomeCalendarMonth extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(prefsProvider).getBool(PrefKeys.homeCalendarMonth) ?? false;

  void toggle() {
    state = !state;
    ref.read(prefsProvider).setBool(PrefKeys.homeCalendarMonth, state);
  }
}

final homeCalendarMonthProvider =
    NotifierProvider<HomeCalendarMonth, bool>(HomeCalendarMonth.new);

final relationTotalsProvider = FutureProvider.family<
    List<({String relation, int sent, int received})>, int>((ref, year) {
  ref.watch(dbVersionProvider);
  return ref.watch(repositoryProvider).relationTotals(year);
});

final yearlyTotalsProvider =
    FutureProvider<List<({int year, int sent, int received})>>((ref) {
  ref.watch(dbVersionProvider);
  return ref.watch(repositoryProvider).yearlyTotals();
});

final allRecordsProvider = FutureProvider<List<GiftRecord>>((ref) {
  ref.watch(dbVersionProvider);
  return ref.watch(repositoryProvider).allRecords();
});
