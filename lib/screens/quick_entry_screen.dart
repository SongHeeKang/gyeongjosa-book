import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../models/person.dart';
import '../services/format.dart';
import '../services/limit_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/amount_input.dart';
import '../widgets/amount_pad.dart';
import '../widgets/coach_mark.dart';
import '../widgets/common.dart';
import '../widgets/person_name_field.dart';
import '../widgets/record_form_sheet.dart';
import '../widgets/screen_coach.dart';

/// 빠른 연속 입력(남의 행사에 보낸 돈): 이름 → 금액 버튼 탭(바로 저장) → 다음 이름.
/// 받은 돈은 받은 돈 적기 화면(ReceiveMoneyScreen)에서 적는다.
/// 축의금 봉투 100개를 빠르게 입력하는 게 목표.
class QuickEntryScreen extends ConsumerStatefulWidget {
  const QuickEntryScreen({super.key, required this.event});
  final Event event;

  @override
  ConsumerState<QuickEntryScreen> createState() => _QuickEntryScreenState();
}

class _QuickEntryScreenState extends ConsumerState<QuickEntryScreen> {
  /// 키보드 위 고정 영역과 제목을 뺀, 자동완성 목록에 쓸 수 있는 높이 계산용
  static const _fixedAreaHeight = 360.0;

  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _amount = TextEditingController();
  final _amountFocus = FocusNode();
  late String _relation;
  String _method = Methods.all.first;
  Person? _selected; // 자동완성에서 고른 기존 사람
  bool _saving = false;
  bool _nameMissing = false;

  /// 이번에 입력한 내역 (최신이 위)
  final _session = <GiftRecord>[];

  /// 내역별 저장 시각 (최근 저장 줄에 보여준다)
  final _savedAt = <int, DateTime>{};

  String get _direction =>
      widget.event.isMine ? Direction.received : Direction.sent;

  @override
  void initState() {
    super.initState();
    _relation =
        ref.read(prefsProvider).getString(PrefKeys.quickEntryRelation) ?? '지인';
    _name.addListener(() {
      // 고른 뒤 이름을 고치면 연결 해제
      if (_selected != null && _name.text.trim() != _selected!.name) {
        setState(() => _selected = null);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    _amount.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _save(int amount) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      // 적어 둔 금액은 그대로 두고 이름부터 받는다
      setState(() => _nameMissing = true);
      _nameFocus.requestFocus();
      return;
    }
    if (amount <= 0) {
      _amountFocus.requestFocus();
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(repositoryProvider);

      // 1) 사람 찾기: 자동완성 선택 > 같은 이름 > 새로 등록
      var person = _selected;
      if (person == null) {
        final same = await repo.findPeopleByExactName(name);
        if (same.isNotEmpty) person = same.first;
      }
      var isNew = false;
      if (person == null) {
        if (!mounted) return;
        // 31번째 새 사람부터 결제 화면. 닫으면 적은 이름 · 금액을 그대로 두고 돌아온다.
        if (!await LimitService.canAddNewPerson(context, ref)) {
          if (mounted && parseAmount(_amount.text) != amount) {
            _amount.text = formatNumber(amount);
          }
          return;
        }
        final id = await repo.insertPerson(Person(
          name: name,
          relation: _relation,
          createdAt: DateTime.now(),
        ));
        person = (await repo.getPerson(id))!;
        isNew = true;
      }

      // 2) 내역 저장
      final record = GiftRecord(
        personId: person.id!,
        eventId: widget.event.id,
        direction: _direction,
        amount: amount,
        method: _method,
        date: widget.event.date,
      );
      final recordId = await repo.insertRecord(record);
      ref.refreshData();

      // 3) 다음 이름으로
      _savedAt[recordId] = DateTime.now();
      setState(() {
        _session.insert(
          0,
          GiftRecord(
            id: recordId,
            personId: person!.id!,
            eventId: widget.event.id,
            direction: _direction,
            amount: amount,
            method: _method,
            date: widget.event.date,
            personName: isNew ? '${person.name} (새로 등록)' : person.name,
          ),
        );
        _selected = null;
        _name.clear();
        _amount.clear();
      });
      _nameFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _undo(GiftRecord r) async {
    await ref.read(repositoryProvider).deleteRecord(r.id!);
    ref.refreshData();
    setState(() => _session.remove(r));
    if (mounted) showSnack(context, '${r.personName} 내역을 지웠어요.');
  }

  /// 방금 적은 항목 수정. 끝나면 고친 내용을 목록에 맞춘다.
  Future<void> _edit(GiftRecord r) async {
    await showRecordForm(context,
        personId: r.personId, existing: r, event: widget.event);
    final records =
        await ref.read(repositoryProvider).recordsForPerson(r.personId);
    if (!mounted) return;
    final index = _session.indexWhere((s) => s.id == r.id);
    if (index < 0) return;
    final saved = records.where((s) => s.id == r.id).firstOrNull;
    setState(() {
      if (saved == null) {
        _session.removeAt(index);
      } else {
        // 이름 옆의 '(새로 등록)' 표시는 그대로 둔다
        _session[index] = GiftRecord(
          id: saved.id,
          personId: saved.personId,
          eventId: saved.eventId,
          direction: saved.direction,
          amount: saved.amount,
          method: saved.method,
          date: saved.date,
          memo: saved.memo,
          eventType: saved.eventType,
          personName: r.personName,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(eventDetailProvider(widget.event.id!)).value;
    final people = ref.watch(allPeopleProvider).value ?? const <Person>[];
    final remainingFree = ref.watch(remainingPeopleProvider).value;
    final hasName = _name.text.trim().isNotEmpty;
    // 키보드가 열려 있으면 바쁜 때: 제목을 줄이고 내역 대신 최근 저장 줄만 보여준다.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final tight = isAmountAreaTight(context);
    final media = MediaQuery.of(context);
    final optionsMax = (media.size.height -
            media.viewInsets.bottom -
            media.padding.vertical -
            _fixedAreaHeight)
        .clamp(72.0, 280.0);

    final relationChips = <Widget>[
      if (_selected == null) ...[
        const SizedBox(height: 12),
        const FieldLabel('새 사람 관계'),
        ChoiceChips(
          options: Relations.all,
          selected: _relation,
          onSelected: (v) {
            setState(() => _relation = v);
            ref.read(prefsProvider).setString(PrefKeys.quickEntryRelation, v);
          },
        ),
      ],
      const SizedBox(height: 12),
      const FieldLabel('방법'),
      ChoiceChips(
        options: Methods.all,
        selected: _method,
        onSelected: (v) => setState(() => _method = v),
      ),
    ];

    Widget recent(int lines) => RecentSavedList(
          items: [
            for (final r in _session.take(lines + 1))
              RecentSavedItem(
                id: r.id!,
                name: r.personName ?? '',
                amount: r.amount,
                savedAt: _savedAt[r.id] ?? DateTime.now(),
              ),
          ],
          lines: lines,
          warn: _session.isNotEmpty &&
              _session.where((r) => r.personId == _session.first.personId).length >
                  1,
          onUndo: _session.isEmpty ? () {} : () => _undo(_session.first),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('빠른 연속 입력'),
        actions: [
          HelpButton(
              screen: CoachScreen.quickEntry,
              onClosed: _nameFocus.requestFocus),
          TestId('btn_done', child: TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('완료'))),
        ],
      ),
      body: SafeArea(
        top: false,
        child: EntryLayout(
          top: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            AutoCoach(
              prefs: ref.read(prefsProvider),
              screen: CoachScreen.quickEntry,
              onClosed: _nameFocus.requestFocus,
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (remainingFree != null && remainingFree <= 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2),
                      child: TestId(
                        'free_remaining',
                        child: Text(
                          remainingFree > 0
                              ? '무료로 $remainingFree명 더 적을 수 있어요'
                              : '무료 30명이 다 찼어요. 이미 등록한 사람은 계속 적을 수 있어요',
                          style: AppText.sub,
                        ),
                      ),
                    ),
                  if (!keyboardOpen && !isShortScreen(context))
                    Text(widget.event.title, style: AppText.sectionTitle),
                  if (detail != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${widget.event.isMine ? '받은' : '보낸'} 사람 ${detail.mainRecords.length}명 · ${formatWon(detail.total)}',
                        style: AppText.listAmount.copyWith(
                            color: AppColors.amount(!widget.event.isMine)),
                      ),
                    ),
                  const SizedBox(height: 4),
                  TestId('input_guest_name', child: PersonNameField(
                    controller: _name,
                    focusNode: _nameFocus,
                    people: people,
                    autofocus: true,
                    hintText: '봉투에 적힌 이름',
                    helperText: _selected != null
                        ? '기존 사람(${_selected!.relation})에 연결돼요'
                        : (hasName ? '처음 보는 이름이면 새로 등록돼요' : null),
                    errorText: _nameMissing ? '이름을 먼저 입력해 주세요' : null,
                    optionsMaxHeight: optionsMax,
                    onEditingComplete: _amountFocus.requestFocus,
                    onSelected: (p) => setState(() => _selected = p),
                    onChanged: () => setState(() => _nameMissing = false),
                  )),
                ],
              ),
            ),
            ],
          ),
          list: keyboardOpen
                  ? LayoutBuilder(
                      builder: (_, constraints) => ListView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.page),
                        children: [
                          if (_session.isNotEmpty)
                            recent(((constraints.maxHeight -
                                        recentWarningHeight(context)) /
                                    recentLineHeight(context))
                                .floor()
                                .clamp(1, 3)),
                          ...relationChips,
                          // 도움말을 띄우면 키보드가 닫히면서 아래 명단이 나타난다
                          const CoachTarget(
                              spot: CoachSpot.quickList,
                              child: SizedBox.shrink()),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.page, 0, AppSpacing.page, 12),
                      children: [
                        if (_session.isNotEmpty) recent(1),
                        ...relationChips,
                        const SizedBox(height: 12),
                        const AppDivider(),
                        CoachTarget(
                          spot: CoachSpot.quickList,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 20, bottom: 4),
                                child: Text(
                                    _session.isEmpty
                                        ? '적은 명단이 여기에 쌓여요'
                                        : '방금 입력한 ${_session.length}건',
                                    style: _session.isEmpty
                                        ? AppText.sub
                                        : AppText.sectionTitle),
                              ),
                              for (final r in _session)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(r.personName ?? ''),
                                  subtitle: Text(
                                      signedWon(r.amount, isSent: r.isSent)),
                                  onTap: () => _edit(r),
                                  trailing: TextButton(
                                    onPressed: () => _undo(r),
                                    child: const Text('취소'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
          compactList: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_session.isNotEmpty) recent(1),
                ...relationChips,
              ],
            ),
          ),
          bottom: [
            AmountField(
              controller: _amount,
              focusNode: _amountFocus,
              onSave: () => _save(parseAmount(_amount.text)),
              tight: tight,
            ),
            CoachTarget(
              spot: CoachSpot.quickAmounts,
              child: AmountPad(
                onAmount: _save,
                buttonHeight:
                    tight ? AppSpacing.padButtonTight : AppSpacing.padButton,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
