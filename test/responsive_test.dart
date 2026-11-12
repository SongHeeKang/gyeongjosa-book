// 작은 화면 · 큰 글씨에서 화면이 잘리거나 넘치지(overflow) 않는지 확인한다.
// 저해상도 폰(320x568dp)과 휴대폰 글자 크기 키움(130%)을 함께 본다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/providers.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/event.dart';
import 'package:gyeongjosa/models/gift_record.dart';
import 'package:gyeongjosa/models/person.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/screens/all_records_screen.dart';
import 'package:gyeongjosa/screens/all_schedules_screen.dart';
import 'package:gyeongjosa/screens/event_detail_screen.dart';
import 'package:gyeongjosa/screens/event_form_screen.dart';
import 'package:gyeongjosa/screens/help_screen.dart';
import 'package:gyeongjosa/screens/main_shell.dart';
import 'package:gyeongjosa/screens/onboarding_screen.dart';
import 'package:gyeongjosa/screens/paywall_screen.dart';
import 'package:gyeongjosa/screens/person_detail_screen.dart';
import 'package:gyeongjosa/screens/pick_my_event_screen.dart';
import 'package:gyeongjosa/screens/whose_event_screen.dart';
import 'package:gyeongjosa/screens/quick_entry_screen.dart';
import 'package:gyeongjosa/screens/reception_form_screen.dart';
import 'package:gyeongjosa/screens/reception_import_screen.dart';
import 'package:gyeongjosa/screens/receive_money_screen.dart';
import 'package:gyeongjosa/services/receive_targets.dart';
import 'package:gyeongjosa/screens/reception_send_screen.dart';
import 'package:gyeongjosa/screens/reception_summary_screen.dart';
import 'package:gyeongjosa/screens/settings_screen.dart';
import 'package:gyeongjosa/services/format.dart';
import 'package:gyeongjosa/services/reception_import.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:gyeongjosa/widgets/person_form_sheet.dart';
import 'package:gyeongjosa/widgets/record_form_sheet.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _today = dateOnly(DateTime.now());

/// 긴 이름 · 큰 금액 · 많은 항목으로 화면을 꽉 채운 표본 데이터
class _DemoRepository extends Repository {
  _DemoRepository() : super(DatabaseHelper.forTest('unused.db'));

  static const _names = ['남궁민수정', '김민수', '이서연', '박지훈', '정하늘', '최유나'];

  final people = [
    for (var i = 0; i < _names.length; i++)
      Person(id: i + 1, name: _names[i], relation: '회사', createdAt: DateTime(2026)),
  ];

  late final records = [
    for (var i = 0; i < 12; i++)
      GiftRecord(
        id: i + 1,
        personId: (i % _names.length) + 1,
        eventId: i.isEven ? 1 : null,
        direction: i.isEven ? '받음' : '보냄',
        amount: i == 0 ? 12345000 : 100000 * (i + 1),
        method: '계좌',
        date: _today.subtract(Duration(days: i)),
        memo: i == 1 ? '회사 동료 결혼식, 봉투 두 개' : null,
        eventType: '결혼',
        needsReview: i == 2,
        personName: _names[i % _names.length],
        personRelation: '회사',
        eventTitle: i.isEven ? '우리 큰딸 결혼식 (서울 강남)' : null,
      ),
  ];

  late final myEvent = Event(
      id: 1,
      type: '결혼',
      title: '우리 큰딸 결혼식 (서울 강남)',
      date: _today.subtract(const Duration(days: 3)),
      isMine: true,
      place: '서울 강남구 아주 긴 이름의 웨딩홀 3층 그랜드볼룸',
      // 받기 설정을 모두 켜서 받은 돈 적기 화면을 가장 꽉 차게
      receiveSides: const ['신랑측', '신부측'],
      mealTicketEnabled: true,
      methodEnabled: true);

  late final schedules = [
    for (var i = 0; i < 4; i++)
      Event(
          id: 10 + i,
          type: '결혼',
          title: '${_names[i]} 결혼식',
          date: _today.add(Duration(days: i - 1)),
          isMine: false,
          personId: i + 1,
          personRelation: '회사'),
  ];

  final reception = Reception(
    id: 'r1',
    title: '홍길동 · 김영희 결혼식 (서울 강남)',
    eventType: '결혼',
    date: DateTime(2026, 11, 15),
    sides: const ['신랑측', '신부측', '혼주 친구'],
    operatorName: '박지원',
    startedAt: DateTime(2026, 11, 15, 11),
  );

  late final entries = [
    for (var i = 0; i < 25; i++)
      ReceptionEntry(
        id: 'e$i',
        receptionId: 'r1',
        name: _names[i % _names.length],
        amount: i == 0 ? 1000000 : 50000 * (1 + i % 4),
        side: reception.sides[i % 3],
        method: i.isEven ? '계좌' : '현금',
        mealTickets: 1 + i % 3,
        memo: i == 0 ? '봉투 두 개' : null,
        createdAt: DateTime(2026, 11, 15, 12, i),
      ),
  ];

  ReceptionPackage get package => ReceptionPackage(reception, entries.reversed.toList());

  List<PersonSummary> get summaries => [
        for (final p in people)
          PersonSummary(person: p, sentTotal: 12345000, receivedTotal: 9876000),
      ];

  @override
  Future<bool> hasAnyData() async => true;
  @override
  Future<int> countPeople() async => people.length;
  @override
  Future<List<PersonSummary>> peopleSummaries() async => summaries;
  @override
  Future<List<Person>> allPeople() async => people;
  @override
  Future<Person?> getPerson(int id) async => people.firstWhere((p) => p.id == id);
  @override
  Future<int> countRecords() async => 30;
  @override
  Future<List<GiftRecord>> recordsForPerson(int personId) async => records;
  @override
  Future<List<GiftRecord>> recordsForEvent(int eventId) async => records;
  @override
  Future<List<GiftRecord>> recentRecords(int limit) async => records.take(limit).toList();
  @override
  Future<List<GiftRecord>> allRecords() async => records;
  @override
  Future<int> countMyEvents() async => 1;
  @override
  Future<List<EventSummary>> eventSummaries() async => [
        EventSummary(event: myEvent, count: 212, total: 15830000),
        for (final e in schedules) EventSummary(event: e, count: 1, total: 100000),
      ];
  @override
  Future<Event?> getEvent(int id) async => myEvent;
  @override
  Future<List<Event>> upcomingSchedules({int? limit}) async =>
      schedules.where((e) => !e.date.isBefore(_today)).take(limit ?? 9).toList();
  @override
  Future<List<Event>> pendingAmountEvents({int? limit}) async => [schedules.first];
  @override
  Future<int> countSchedules() async => schedules.length;
  @override
  Future<List<Event>> myEvents() async => [myEvent];
  @override
  Future<List<Event>> allEvents() async => [myEvent, ...schedules];
  @override
  Future<List<ReceptionSummary>> receptionSummaries() async =>
      [ReceptionSummary(reception, entries.length, 15830000)];
  @override
  Future<ReceptionPackage?> getReceptionPackage(String id) async => package;
  @override
  Future<bool> hasDummyData() async => false;
  @override
  Future<int> countReceptionEntries() async => entries.length;
  @override
  Future<ImportPlan> planImport(ReceptionPackage package,
          {int? eventId, int? maxPeople}) async =>
      buildImportPlan(
        entries: package.entries,
        importedIds: const {},
        peopleByName: const {},
        namesInEvent: const {},
        newPersonSlots: maxPeople,
      );
  @override
  Future<({int sent, int received, int sentCount, int receivedCount})> yearTotals(
          int year) async =>
      (sent: 123456000, received: 98765000, sentCount: 123, receivedCount: 98);
  @override
  Future<List<int>> recordYears() async => [_today.year - 1, _today.year];
  @override
  Future<List<({int month, int sent, int received})>> monthlyTotals(int year) async => [
        for (var m = 1; m <= 12; m++) (month: m, sent: 1500000 * m, received: 900000 * m),
      ];
  @override
  Future<List<({String relation, int sent, int received})>> relationTotals(int year) async =>
      [(relation: '회사', sent: 12345000, received: 9876000)];
  @override
  Future<List<({int year, int sent, int received})>> yearlyTotals() async =>
      [(year: _today.year, sent: 12345000, received: 9876000)];
}

/// 화면 크기 · 글자 크기 조합
const _sizes = [
  ('작은 폰 320x568, 글자 130%', Size(320, 568), 1.3),
  ('작은 폰 320x568, 글자 100%', Size(320, 568), 1.0),
  ('보통 폰 360x640, 글자 150%', Size(360, 640), 1.5),
];

/// 화면 하나를 띄우는 방법. [open]은 띄운 뒤 추가로 할 일(탭 이동, 버튼 누르기 등).
class _Case {
  const _Case(this.name, this.build, {this.open, this.keyboard = false});
  final String name;
  final Widget Function(_DemoRepository repo) build;
  final Future<void> Function(WidgetTester tester)? open;

  /// 키보드가 올라온 상태(화면 아래 260dp가 가려짐)도 본다
  final bool keyboard;
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

/// 버튼만 있는 화면에서 아래 창(sheet)을 연다.
Widget _launcher(Future<void> Function(BuildContext context) open) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(onPressed: () => open(context), child: const Text('열기')),
        ),
      ),
    );

final _cases = <_Case>[
  _Case('홈', (_) => const MainShell()),
  _Case('사람 탭', (_) => const MainShell(), open: (t) => _tapText(t, '사람')),
  _Case('내 행사 탭', (_) => const MainShell(), open: (t) => _tapText(t, '내 행사')),
  _Case('통계 탭', (_) => const MainShell(), open: (t) => _tapText(t, '통계')),
  _Case('기록하기 메뉴', (_) => const MainShell(), open: (t) async {
    await t.tap(find.byTooltip('기록하기'));
    await t.pumpAndSettle();
  }),
  for (var page = 1; page <= 4; page++)
    _Case('첫 실행 가이드 $page장', (_) => const OnboardingScreen(replay: true),
        open: (t) async {
      for (var i = 1; i < page; i++) {
        await t.tap(find.text('다음'));
        await t.pumpAndSettle();
      }
    }),
  _Case('설정', (_) => const SettingsScreen()),
  _Case('사용 방법', (_) => const HelpScreen()),
  _Case('결제', (_) => const PaywallScreen(reason: '312명 중 20명까지 가져올 수 있어요.')),
  _Case('사람 상세', (_) => const PersonDetailScreen(personId: 1)),
  _Case('내 행사 상세', (_) => const EventDetailScreen(eventId: 1)),
  _Case('전체 기록', (_) => const AllRecordsScreen()),
  _Case('일정 전체', (_) => const AllSchedulesScreen()),
  _Case('일정 추가', (_) => const EventFormScreen(), keyboard: true),
  _Case('내 행사 만들기', (_) => const EventFormScreen(initialIsMine: true), keyboard: true),
  _Case('누구 행사인가요?', (_) => const WhoseEventScreen()),
  _Case('어느 행사에 적을까요?', (_) => const PickMyEventScreen()),
  _Case('내 행사 받기 설정', (r) => ReceptionFormScreen.myEvent(event: r.myEvent),
      keyboard: true),
  _Case('대신 받기 행사 설정', (_) => const ReceptionFormScreen(), open: (t) async {
    // 아래쪽 버튼은 화면 밖이라 아직 그려지지 않았을 수 있어 스크롤해서 찾는다
    await t.scrollUntilVisible(find.text('식권도 기록'), 120,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.text('식권도 기록'));
    await t.pumpAndSettle();
  }, keyboard: true),
  _Case('받은 돈 적기 (대신 받기)',
      (_) => const ReceiveMoneyScreen(target: ReceptionTarget('r1')),
      keyboard: true),
  _Case('받은 돈 적기 (내 행사)',
      (_) => const ReceiveMoneyScreen(target: MyEventTarget(1)),
      keyboard: true),
  _Case('대신 받은 장부', (_) => const ReceptionSummaryScreen(receptionId: 'r1')),
  _Case('장부 보내기', (r) => ReceptionSendScreen(package: r.package)),
  _Case('장부 보내기 (요약 메시지)', (r) => ReceptionSendScreen(package: r.package),
      open: (t) => _tapText(t, '요약 메시지')),
  _Case('받은 장부 가져오기', (r) => ReceptionImportScreen(package: r.package)),
  _Case('빠른 연속 입력 (보낸 돈)', (r) => QuickEntryScreen(event: r.schedules.first),
      keyboard: true),
  _Case(
      '내역 입력창',
      (r) => _launcher((c) => showRecordForm(c, personId: 1)),
      open: (t) => _tapText(t, '열기'),
      keyboard: true),
  _Case(
      '내역 수정창(확인 필요)',
      (r) => _launcher((c) => showRecordForm(c, personId: 1, existing: r.records[2])),
      open: (t) => _tapText(t, '열기')),
  _Case('사람 추가창', (r) => _launcher((c) => showPersonFormForTest(c)),
      open: (t) => _tapText(t, '열기'), keyboard: true),
];

/// 사람 추가창은 WidgetRef가 필요해 Consumer 안에서 연다.
Future<void> showPersonFormForTest(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => UncontrolledProviderScope(
        container: container, child: const PersonFormSheet()),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  for (final (sizeName, size, textScale) in _sizes) {
    group(sizeName, () {
      for (final c in _cases) {
        for (final keyboardOpen in [false, if (c.keyboard) true]) {
          final name = keyboardOpen ? '${c.name} (키보드 열림)' : c.name;
          testWidgets(name, (tester) async {
            tester.view.physicalSize = size * 2;
            tester.view.devicePixelRatio = 2;
            tester.platformDispatcher.textScaleFactorTestValue = textScale;
            addTearDown(tester.view.reset);
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

            // 넘침(overflow) 오류를 모두 모은다
            final problems = <String>[];
            final previous = FlutterError.onError;
            FlutterError.onError = (details) {
              final text = details.exceptionAsString();
              if (text.contains('overflowed') || text.contains('RenderFlex')) {
                // 어느 위젯(파일:줄)에서 넘쳤는지 함께 적는다
                final where = RegExp(r'lib/[a-z_/]+\.dart:\d+')
                    .allMatches(details.toString())
                    .map((m) => m.group(0))
                    .toSet()
                    .join(', ');
                problems.add('${text.split('\n').first} @ $where');
              } else {
                previous?.call(details);
              }
            };

            try {
            SharedPreferences.setMockInitialValues({
              'flutter.${PrefKeys.onboardingSeen}': true,
              'flutter.${PrefKeys.restorePromptDone}': true,
              'flutter.${PrefKeys.notifPermissionAsked}': true,
              for (final s in ['home', 'recordMenu', 'people', 'myEvents', 'eventDetail',
                  'stats', 'reception', 'quickEntry'])
                'flutter.coach_seen_$s': true,
            });
            final prefs = await SharedPreferences.getInstance();
            final repo = _DemoRepository();
            await tester.pumpWidget(ProviderScope(
              overrides: [
                prefsProvider.overrideWithValue(prefs),
                repositoryProvider.overrideWithValue(repo),
              ],
              child: MaterialApp(theme: buildAppTheme(), home: c.build(repo)),
            ));
            await tester.pumpAndSettle();
            if (c.open != null) await c.open!(tester);
            if (keyboardOpen) {
              tester.view.viewInsets = const FakeViewPadding(bottom: 260 * 2);
              await tester.pumpAndSettle();
            }
            } finally {
              // 테스트가 끝나기 전에 원래 오류 처리로 되돌려야 한다
              FlutterError.onError = previous;
            }
            expect(problems, isEmpty, reason: problems.toSet().join('\n'));
          });
        }
      }
    });
  }
}
