import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/event.dart';
import '../services/format.dart';
import '../services/limit_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/pro_gate.dart';
import '../widgets/test_id.dart';
import 'whose_event_screen.dart';

/// 받은 돈 적기 > 내 행사: '어느 행사에 적을까요?'
/// [+ 새 내 행사]는 한도에 닿았으면 자물쇠 · 프로 표시, 누르면 바로 결제 화면.
class PickMyEventScreen extends ConsumerStatefulWidget {
  const PickMyEventScreen({super.key});

  @override
  ConsumerState<PickMyEventScreen> createState() => _PickMyEventScreenState();
}

class _PickMyEventScreenState extends ConsumerState<PickMyEventScreen> {
  void _open(Event event) =>
      Navigator.pushReplacement(context, myEventReceiveRoute(event));

  Future<void> _createNew() async {
    final id = await createMyEvent(context, ref);
    if (id == null || !mounted) return;
    final event = await ref.read(repositoryProvider).getEvent(id);
    if (event == null || !mounted) return;
    _open(event);
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventSummariesProvider);
    final locked = ref.watch(myEventLimitReachedProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('받은 돈 적기')),
      body: AsyncBody(
        value: events,
        builder: (all) {
          final mine = all.where((s) => s.event.isMine).toList();
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.page, 8, AppSpacing.page, 12),
                child: Text('어느 행사에 적을까요?', style: AppText.appTitle),
              ),
              for (final s in mine)
                TestId('pick_event_${s.event.title}',
                    child: EventTile(
                      event: s.event,
                      subtitle:
                          '${formatDate(s.event.date)} · 받은 사람 ${s.count}명 · ${formatWon(s.total)}',
                      onTap: () => _open(s.event),
                    )),
              const AppDivider(),
              TestId('btn_pick_new_event',
                  child: InkWell(
                    onTap: _createNew,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.page, vertical: 18),
                      child: Row(
                        children: [
                          const Icon(Icons.add, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('새 내 행사',
                                style: AppText.listName
                                    .copyWith(color: AppColors.primary)),
                          ),
                          if (locked) const ProLockMark(),
                        ],
                      ),
                    ),
                  )),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
