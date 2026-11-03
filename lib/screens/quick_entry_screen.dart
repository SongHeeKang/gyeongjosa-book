import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../models/gift_record.dart';
import '../models/person.dart';
import '../services/format.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/amount_input.dart';
import '../widgets/common.dart';
import '../widgets/pro_gate.dart';

/// 빠른 연속 입력: 이름 → 금액 버튼 탭(바로 저장) → 다음 이름.
/// 축의금 봉투 100개를 빠르게 입력하는 게 목표.
class QuickEntryScreen extends ConsumerStatefulWidget {
  const QuickEntryScreen({super.key, required this.event});
  final Event event;

  @override
  ConsumerState<QuickEntryScreen> createState() => _QuickEntryScreenState();
}

class _QuickEntryScreenState extends ConsumerState<QuickEntryScreen> {
  static const _quickAmounts = [30000, 50000, 100000, 200000];

  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  final _amount = TextEditingController();
  late String _relation;
  String _method = Methods.all.first;
  Person? _selected; // 자동완성에서 고른 기존 사람
  bool _saving = false;

  /// 이번에 입력한 내역 (최신이 위)
  final _session = <GiftRecord>[];

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
    super.dispose();
  }

  Future<void> _save(int amount) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showSnack(context, '이름을 먼저 입력해 주세요.');
      _nameFocus.requestFocus();
      return;
    }
    if (amount <= 0) {
      showSnack(context, '금액 버튼을 누르거나 금액을 입력해 주세요.');
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
        // 31번째 사람부터 결제 화면
        if (!await ensureCanAddPerson(context, ref)) return;
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

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(eventDetailProvider(widget.event.id!)).value;
    final people = ref.watch(allPeopleProvider).value ?? const <Person>[];
    final hasName = _name.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('빠른 연속 입력'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('완료')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, 0, AppSpacing.page, 32),
        children: [
          Text(widget.event.title, style: AppText.sectionTitle),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${widget.event.isMine ? '받은' : '보낸'} 사람 ${detail.mainRecords.length}명 · ${formatWon(detail.total)}',
                style: AppText.listAmount.copyWith(
                    color: AppColors.amount(!widget.event.isMine)),
              ),
            ),
          const SizedBox(height: 16),
          RawAutocomplete<Person>(
            textEditingController: _name,
            focusNode: _nameFocus,
            displayStringForOption: (p) => p.name,
            optionsBuilder: (value) {
              final q = value.text.trim();
              if (q.isEmpty) return const Iterable<Person>.empty();
              return people.where((p) => p.name.contains(q)).take(6);
            },
            onSelected: (p) => setState(() => _selected = p),
            fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
                TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '이름',
                hintText: '봉투에 적힌 이름',
                helperText: _selected != null
                    ? '기존 사람(${_selected!.relation})에 연결돼요'
                    : (hasName ? '처음 보는 이름이면 새로 등록돼요' : null),
              ),
            ),
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: 280,
                      maxWidth: MediaQuery.of(context).size.width -
                        AppSpacing.page * 2),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final p in options)
                        ListTile(
                          title: Text(p.name),
                          subtitle: Text([p.relation, if ((p.phone ?? '').isNotEmpty) p.phone!].join(' · ')),
                          onTap: () => onSelected(p),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
          const SizedBox(height: 16),
          const FieldLabel('금액을 누르면 바로 저장돼요'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.6,
            children: [
              for (final a in _quickAmounts)
                FilledButton(
                  onPressed: _saving ? null : () => _save(a),
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(
                        fontFamily: AppText.fontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                  ),
                  child: Text('${formatManWon(a)}원'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsFormatter()],
                  style: const TextStyle(fontSize: 17),
                  decoration: const InputDecoration(
                      labelText: '다른 금액', suffixText: '원'),
                  onSubmitted: (t) => _save(parseAmount(t)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => _save(parseAmount(_amount.text)),
                  child: const Text('저장'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ChoiceChips(
            options: Methods.all,
            selected: _method,
            onSelected: (v) => setState(() => _method = v),
          ),
          if (_session.isNotEmpty) ...[
            const SizedBox(height: 12),
            const AppDivider(),
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 4),
              child: Text('방금 입력한 ${_session.length}건', style: AppText.sectionTitle),
            ),
            for (final r in _session)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.personName ?? ''),
                subtitle: Text(signedWon(r.amount, isSent: r.isSent)),
                trailing: TextButton(
                  onPressed: () => _undo(r),
                  child: const Text('취소'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
