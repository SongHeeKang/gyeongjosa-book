import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/constants.dart';
import '../models/event.dart';
import '../models/reception.dart';
import '../services/format.dart';
import '../services/reception_file_service.dart';
import '../services/reception_import.dart';
import '../services/limit_service.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import '../widgets/common.dart';
import '../widgets/pro_gate.dart';
import 'event_detail_screen.dart';

/// 내 행사의 [장부 가져오기]: 파일을 골라 미리보기 화면으로 간다.
Future<void> pickAndOpenImport(BuildContext context, {int? eventId}) async {
  try {
    final package = await ReceptionFileService.pick();
    if (package == null || !context.mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => ReceptionImportScreen(
                package: package, initialEventId: eventId)));
  } on FormatException catch (e) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('가져올 수 없어요'),
          content: Text(e.message),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
          ],
        ),
      );
    }
  } catch (e) {
    if (context.mounted) showSnack(context, '파일을 읽지 못했어요: $e');
  }
}

/// 미리보기 → 합칠 내 행사 고르기 → 가져오기
class ReceptionImportScreen extends ConsumerStatefulWidget {
  const ReceptionImportScreen(
      {super.key, required this.package, this.initialEventId});
  final ReceptionPackage package;

  /// 내 행사 상세에서 들어오면 그 행사에 합친다.
  final int? initialEventId;

  @override
  ConsumerState<ReceptionImportScreen> createState() =>
      _ReceptionImportScreenState();
}

class _ReceptionImportScreenState extends ConsumerState<ReceptionImportScreen> {
  /// null이면 새 장부 만들기
  int? _eventId;
  bool _targetChosen = false;
  ImportPlan? _plan;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialEventId != null) {
      _eventId = widget.initialEventId;
      _targetChosen = true;
    }
    _refreshPlan();
  }

  Future<void> _refreshPlan() async {
    final plan = await ref
        .read(repositoryProvider)
        .planImport(widget.package, eventId: _eventId);
    if (mounted) setState(() => _plan = plan);
  }

  /// 처음에는 같은 이름 · 같은 날짜의 내 장부를 골라 둔다 (폰 2대의 파일을 한 장부로).
  void _preselect(List<Event> mine) {
    if (_targetChosen) return;
    _targetChosen = true;
    final r = widget.package.reception;
    for (final e in mine) {
      if (e.title == r.title && toDbDate(e.date) == toDbDate(r.date)) {
        _eventId = e.id;
        _refreshPlan();
        return;
      }
    }
  }

  void _select(int? eventId) {
    setState(() => _eventId = eventId);
    _refreshPlan();
  }

  Event _newEvent() {
    final r = widget.package.reception;
    return Event(
      type: EventTypes.all.contains(r.eventType) ? r.eventType : '기타',
      title: r.title.isEmpty ? '받은 장부' : r.title,
      date: r.date,
      isMine: true,
      notify: false,
    );
  }

  /// 사람 30명 한도 처리. 넘으면 안내 후 결제 화면을 띄우고,
  /// 결제하지 않으면 한도까지만 가져올지 묻는다. 파일은 그대로 남으니 나중에 마저 가져올 수 있다.
  Future<({bool proceed, int? limit})> _resolvePeopleLimit() async {
    final limit = LimitService.importPeopleLimit(ref);
    if (limit == null) return (proceed: true, limit: null);
    final plan = await ref.read(repositoryProvider).planImport(widget.package,
        eventId: _eventId, maxPeople: limit);
    if (plan.skippedByLimit == 0) {
      return (proceed: true, limit: limit);
    }
    if (!mounted) return (proceed: false, limit: null);
    final upgraded = await showPaywall(context, ref,
        reason: '${plan.remaining}명 중 ${plan.items.length}명까지 가져올 수 있어요.');
    if (upgraded) return (proceed: true, limit: null);
    if (!mounted) return (proceed: false, limit: null);
    if (plan.items.isEmpty) {
      showSnack(context, '프로를 구매한 뒤 같은 파일을 다시 가져올 수 있어요.');
      return (proceed: false, limit: null);
    }
    final partial = await confirmDialog(context,
        title: '${plan.items.length}명만 먼저 가져올까요?',
        message:
            '나머지 ${plan.skippedByLimit}명은 프로를 구매한 뒤 같은 파일을 다시 가져오면 들어와요. 파일을 지우지 말고 보관해 주세요.',
        okText: '${plan.items.length}명 가져오기');
    return (proceed: partial, limit: limit);
  }

  Future<void> _import() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final repo = ref.read(repositoryProvider);
      // 내 행사 한도: 새로 만들 때만 확인
      if (_eventId == null && !await LimitService.canCreateMyEvent(context, ref)) return;
      if (!mounted) return;
      final maxPeople = await _resolvePeopleLimit();
      if (!maxPeople.proceed) return;
      final result = await repo.applyImport(
        widget.package,
        eventId: _eventId,
        newEvent: _eventId == null ? _newEvent() : null,
        maxPeople: maxPeople.limit,
      );
      ref.refreshData();
      if (!mounted) return;
      await _showResult(result.plan);
      if (!mounted) return;
      if (widget.initialEventId == result.eventId) {
        Navigator.pop(context);
        return;
      }
      Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
              builder: (_) => EventDetailScreen(eventId: result.eventId)));
    } catch (e) {
      if (mounted) showSnack(context, '가져오지 못했어요. 기존 기록은 그대로예요. ($e)');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showResult(ImportPlan plan) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${plan.items.length}명을 가져왔어요'),
          content: Text([
            if (plan.alreadyImported > 0)
              '이미 가져온 ${plan.alreadyImported}명은 건너뛰었어요.',
            if (plan.reviewCount > 0)
              '동명이인일 수 있는 ${plan.reviewCount}명은 \'확인 필요\'로 표시했어요.',
            if (plan.skippedByLimit > 0)
              '${plan.skippedByLimit}명은 아직 못 가져왔어요. 프로를 구매한 뒤 같은 파일을 다시 가져오면 들어와요.',
          ].join('\n')),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final summaries = ref.watch(eventSummariesProvider);
    final r = widget.package.reception;
    final totals = widget.package.totals;
    final plan = _plan;
    final mine = (summaries.value ?? const <EventSummary>[])
        .where((s) => s.event.isMine)
        .toList();
    if (summaries.hasValue) _preselect([for (final s in mine) s.event]);
    final hasWork = plan != null && plan.remaining > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('받은 장부 가져오기')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title, style: AppText.sectionTitle),
                const SizedBox(height: 4),
                Text(
                    '${formatDate(r.date)}${r.operatorName.isEmpty ? '' : ' · 접수 ${r.operatorName}'}',
                    style: AppText.sub),
                const SizedBox(height: 16),
                TestId('import_preview_total', child: Text('${totals.count}명 · ${formatWon(totals.amount)}',
                    style: AppText.summaryAmount
                        .copyWith(color: AppColors.primary))),
                if (plan != null && plan.alreadyImported > 0) ...[
                  const SizedBox(height: 8),
                  Text('이미 가져온 ${plan.alreadyImported}명은 다시 저장하지 않아요.',
                      style: AppText.body),
                ],
                if (plan != null && plan.reviewCount > 0) ...[
                  const SizedBox(height: 8),
                  Text('동명이인일 수 있는 ${plan.reviewCount}명은 \'확인 필요\'로 표시돼요.',
                      style: AppText.body),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          const AppDivider(),
          const SectionTitle('어느 내 행사에 합칠까요?'),
          RadioGroup<int?>(
            groupValue: _eventId,
            onChanged: _select,
            child: Column(
              children: [
                for (final s in mine)
                  RadioListTile<int?>(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.page),
                    value: s.event.id,
                    title: Text(s.event.title, style: AppText.listName),
                    subtitle: Text(
                        '${formatDate(s.event.date)} · 받은 사람 ${s.count}명'),
                  ),
                RadioListTile<int?>(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                  value: null,
                  title: const Text('새 내 행사 만들기', style: AppText.listName),
                  subtitle: Text(r.title),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.page, 20, AppSpacing.page, 32),
            child: SizedBox(
              height: AppSpacing.receptionButton,
              child: TestId('btn_import_confirm', child: FilledButton(
                onPressed: hasWork && !_working ? _import : null,
                child: Text(plan == null || hasWork
                    ? '${plan?.remaining ?? totals.count}명 가져오기'
                    : '모두 가져왔어요'),
              )),
            ),
          ),
        ],
      ),
    );
  }
}
