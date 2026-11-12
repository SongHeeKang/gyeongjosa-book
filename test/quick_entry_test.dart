import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyeongjosa/data/database_helper.dart';
import 'package:gyeongjosa/data/providers.dart';
import 'package:gyeongjosa/data/repository.dart';
import 'package:gyeongjosa/models/constants.dart';
import 'package:gyeongjosa/models/event.dart';
import 'package:gyeongjosa/models/gift_record.dart';
import 'package:gyeongjosa/models/person.dart';
import 'package:gyeongjosa/models/reception.dart';
import 'package:gyeongjosa/screens/receive_money_screen.dart';
import 'package:gyeongjosa/services/receive_targets.dart';
import 'package:gyeongjosa/services/settings_service.dart';
import 'package:gyeongjosa/theme/app_theme.dart';
import 'package:gyeongjosa/widgets/amount_pad.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _event = Event(
    id: 1, type: '결혼', title: '내 결혼식', date: DateTime(2026, 11, 1), isMine: true);

class _FakeRepository extends Repository {
  _FakeRepository() : super(DatabaseHelper.forTest('unused.db'));
  final people = <Person>[];
  final records = <GiftRecord>[];

  @override
  Future<List<Person>> allPeople() async => people;
  @override
  Future<List<Person>> findPeopleByExactName(String name) async =>
      people.where((p) => p.name == name).toList();
  @override
  Future<int> countPeople() async => people.length;
  @override
  Future<int> insertPerson(Person person) async {
    final id = people.length + 1;
    people.add(Person(
        id: id,
        name: person.name,
        relation: person.relation,
        createdAt: person.createdAt));
    return id;
  }

  @override
  Future<Person?> getPerson(int id) async => people[id - 1];
  @override
  Future<int> insertRecord(GiftRecord record) async {
    records.add(record);
    return records.length;
  }

  @override
  Future<void> deleteRecord(int id) async => records.removeLast();
  @override
  Future<Event?> getEvent(int id) async => _event;
  @override
  // 실제 DB처럼 최신이 앞이고 사람 이름이 붙어 있다
  Future<List<GiftRecord>> recordsForEvent(int eventId) async => [
        for (final (i, r) in records.indexed.toList().reversed)
          GiftRecord(
            id: i + 1,
            personId: r.personId,
            eventId: r.eventId,
            direction: r.direction,
            amount: r.amount,
            date: r.date,
            personName: people[r.personId - 1].name,
          ),
      ];
  // 접수 화면 비교용
  @override
  Future<ReceptionPackage?> getReceptionPackage(String id) async =>
      ReceptionPackage(
          Reception(
            id: 'r1',
            title: '접수',
            eventType: '결혼',
            date: DateTime(2026, 11, 1),
            sides: const ['전체'],
            operatorName: '',
            startedAt: DateTime(2026, 11, 1),
          ),
          const []);
}

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  Future<_FakeRepository> open(WidgetTester tester, Widget home,
      {Size size = const Size(411, 914), double keyboard = 0}) async {
    tester.view.devicePixelRatio = 2.625;
    tester.view.physicalSize = size * 2.625;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 2.625);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetViewInsets);
    SharedPreferences.setMockInitialValues(
        {'flutter.${PrefKeys.notifPermissionAsked}': true});
    final prefs = await SharedPreferences.getInstance();
    final repo = _FakeRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        repositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: home),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Finder nameField() => find.widgetWithText(TextField, '이름');
  Finder amountField() => find.widgetWithText(TextField, '금액');
  // 받은 돈 적기 > 내 행사 (예전 '받은 명단 직접 입력' 자리)
  const quick = ReceiveMoneyScreen(target: MyEventTarget(1));

  testWidgets('내 행사와 대신 받기의 금액 버튼 8개가 같고, 식권을 끈 내 행사는 칩이 없다', (tester) async {
    const labels = ['5만', '10만', '15만', '20만', '25만', '30만', '50만', '100만'];
    await open(tester, ReceiveMoneyScreen(target: ReceptionTarget('r1')));
    final reception = {
      for (final l in labels) l: tester.getRect(find.text(l)),
    };
    final receptionButton =
        tester.getSize(find.widgetWithText(FilledButton, '5만'));

    await open(tester, quick);
    expect(tester.takeException(), isNull);
    expect(find.byType(AmountPad), findsOneWidget);
    expect(find.byType(AmountField), findsOneWidget);
    for (final l in labels) {
      expect(tester.getRect(find.text(l)), reception[l], reason: l);
    }
    expect(tester.getSize(find.widgetWithText(FilledButton, '5만')),
        receptionButton);
    expect(receptionButton.height, AppSpacing.padButton);

    // 접수에만 있는 것은 넣지 않는다
    expect(find.widgetWithText(OutlinedButton, '4+'), findsNothing);
    expect(find.text('식권'), findsNothing);
    expect(find.text('3만원'), findsNothing);
  });

  testWidgets('금액 버튼: 진동 뒤 바로 저장, 이름칸만 비우고 커서는 이름칸, 받음으로 저장', (tester) async {
    final repo = await open(tester, quick);
    await tester.enterText(nameField(), '김철수');
    await tester.tap(find.text('10만'));
    await tester.pumpAndSettle();

    expect(repo.records.single.amount, 100000);
    expect(repo.records.single.direction, Direction.received);
    expect(repo.records.single.eventId, 1);
    final name = tester.widget<TextField>(nameField());
    expect(name.controller!.text, isEmpty);
    expect(name.focusNode!.hasFocus, isTrue);
  });

  testWidgets('다음으로 금액칸, 쉼표와 7만원 표시, 완료로 저장, 이름 없으면 금액은 남긴다', (tester) async {
    final repo = await open(tester, quick);
    await tester.enterText(amountField(), '70000');
    await tester.pump();
    expect(tester.widget<TextField>(amountField()).controller!.text, '70,000');
    expect(find.text('7만원'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.records, isEmpty);
    expect(find.text('이름을 먼저 입력해 주세요'), findsOneWidget);
    expect(tester.widget<TextField>(amountField()).controller!.text, '70,000');

    await tester.enterText(nameField(), '이영희');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(amountField()).focusNode!.hasFocus, isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.records.single.amount, 70000);
    expect(tester.widget<TextField>(nameField()).focusNode!.hasFocus, isTrue);
  });

  testWidgets('키보드가 열리면 최근 저장 3줄, 최신이 맨 위, 되돌리기는 하나', (tester) async {
    final repo = await open(tester, quick, keyboard: 300);
    for (final n in ['첫째', '둘째', '셋째', '넷째']) {
      await tester.enterText(nameField(), n);
      await tester.tap(find.text('5만'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(RecentSavedList), findsOneWidget);
    expect(find.textContaining('첫째'), findsNothing);
    final top = tester.getTopLeft(find.textContaining('넷째')).dy;
    expect(top, lessThan(tester.getTopLeft(find.textContaining('셋째')).dy));
    expect(find.text('되돌리기'), findsOneWidget);

    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();
    expect(repo.records.length, 3);
  });

  testWidgets('작은 폰에서 키보드가 열려도 넘치지 않는다', (tester) async {
    for (final size in const [Size(360, 640), Size(360, 780)]) {
      await open(tester, quick, size: size, keyboard: 300);
      await tester.enterText(nameField(), '김철수');
      await tester.pump();
      await tester.tap(find.text('5만'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('이름 자동완성 목록이 금액 버튼을 가리지 않아 바로 누를 수 있다', (tester) async {
    final repo = await open(tester, quick, keyboard: 300);
    for (var i = 0; i < 6; i++) {
      await repo.insertPerson(
          Person(name: '김사람$i', relation: '친구', createdAt: DateTime(2026)));
    }
    await tester.pumpWidget(const SizedBox());
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        repositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: quick),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(nameField(), '김');
    await tester.pumpAndSettle();
    expect(find.textContaining('김사람0'), findsOneWidget);
    await tester.tap(find.text('50만'));
    await tester.pumpAndSettle();
    expect(repo.records.single.amount, 500000);
  });
}
