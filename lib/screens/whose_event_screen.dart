import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../models/event.dart';
import '../services/limit_service.dart';
import '../services/receive_targets.dart';
import '../theme/app_theme.dart';
import '../widgets/test_id.dart';
import 'event_form_screen.dart';
import 'pick_my_event_screen.dart';
import 'receive_money_screen.dart';
import 'reception_form_screen.dart';

/// 새 내 행사 만들기. 내 행사가 생기는 모든 입구가 이것을 쓴다.
/// 버튼을 누른 순간 한도를 보고, 닿았으면 바로 결제 화면(닫으면 null, 구매하면 만들기 화면).
/// 만들었으면 새 행사 id.
Future<int?> createMyEvent(BuildContext context, WidgetRef ref) async {
  if (!await LimitService.canCreateMyEvent(context, ref)) return null;
  if (!context.mounted) return null;
  return Navigator.push<int>(
      context,
      MaterialPageRoute<int>(
          builder: (_) => const EventFormScreen(initialIsMine: true)));
}

/// 내 행사의 받은 돈 적기를 연다. 처음이면 행사 설정(구분 · 식권 · 결제 방법)부터 묻는다.
Route<void> myEventReceiveRoute(Event event) => MaterialPageRoute<void>(
    builder: (_) => event.receiveSettingsDone
        ? ReceiveMoneyScreen(target: MyEventTarget(event.id!))
        : ReceptionFormScreen.myEvent(event: event));

/// 대신 받은 장부의 받은 돈 적기
Route<void> receptionReceiveRoute(String receptionId) =>
    MaterialPageRoute<void>(
        builder: (_) =>
            ReceiveMoneyScreen(target: ReceptionTarget(receptionId)));

/// 질문 화면 '누구 행사인가요?'. 연필 > [받은 돈 적기]에서 열린다.
/// 항상 물어본다(마지막 선택을 기억해 건너뛰지 않음). 도움말은 없다.
class WhoseEventScreen extends ConsumerStatefulWidget {
  const WhoseEventScreen({super.key});

  @override
  ConsumerState<WhoseEventScreen> createState() => _WhoseEventScreenState();
}

class _WhoseEventScreenState extends ConsumerState<WhoseEventScreen> {
  bool _busy = false;

  Future<void> _mine() async {
    if (_busy) return;
    _busy = true;
    try {
      final repo = ref.read(repositoryProvider);
      final mine = await repo.myEvents();
      if (!mounted) return;
      if (mine.isNotEmpty) {
        await Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(
                builder: (_) => const PickMyEventScreen()));
        return;
      }
      // 내 행사가 없으면 바로 만들기 화면
      final id = await createMyEvent(context, ref);
      if (id == null || !mounted) return;
      final event = await repo.getEvent(id);
      if (event == null || !mounted) return;
      await Navigator.pushReplacement(context, myEventReceiveRoute(event));
    } finally {
      _busy = false;
    }
  }

  void _other() => Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => const ReceptionFormScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('받은 돈 적기')),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(AppSpacing.page, 8, AppSpacing.page, 32),
        children: [
          const Text('누구 행사인가요?', style: AppText.appTitle),
          const SizedBox(height: 20),
          TestId('whose_mine',
              child: _WhoseCard(
                icon: Icons.celebration_outlined,
                title: '내 행사',
                description: '내 결혼식 · 돌잔치처럼 내가 받는 행사',
                note: '내 장부에 저장 · 행사 1개 무료',
                onTap: _mine,
              )),
          const SizedBox(height: 12),
          TestId('whose_other',
              child: _WhoseCard(
                icon: Icons.volunteer_activism_outlined,
                title: '다른 사람 행사',
                description: '친구 · 가족 행사에서 대신 받아요',
                note: '끝나면 혼주에게 장부 보내기 · 무료',
                onTap: _other,
              )),
        ],
      ),
    );
  }
}

/// 질문 화면의 큰 카드 (높이 96 이상): 제목 + 한 줄 설명 + 회색 작은 글씨
class _WhoseCard extends StatelessWidget {
  const _WhoseCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.note,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String description;
  final String note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 96),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.sectionTitle),
                      const SizedBox(height: 4),
                      Text(description, style: AppText.body),
                      const SizedBox(height: 4),
                      Text(note, style: AppText.sub),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.icon),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
