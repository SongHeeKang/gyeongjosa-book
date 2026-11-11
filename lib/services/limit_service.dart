import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../widgets/pro_gate.dart';
import 'limits.dart';
import 'pro_service.dart';

/// 무료 한도(사람 30명) 검사를 한 곳에 모았다.
/// 새 사람이 생기는 모든 경로가 이것을 거친다:
/// 사람 탭 추가 · 보냈어요 · '얼마 내셨어요?' 카드(모두 사람 추가 창), 일정 추가,
/// 받은 명단 직접 입력, 확인 필요 내역의 '다른 사람', 장부 가져오기.
/// 행사장 접수는 사람 목록에 넣지 않으므로 검사하지 않는다.
/// 이미 등록된 사람에게 기록을 더하거나 보기 · 수정 · 삭제하는 것은 막지 않는다.
class LimitService {
  /// 무료로 더 등록할 수 있는 사람 수. 프로면 null(제한 없음).
  static Future<int?> remainingPeople(WidgetRef ref) async {
    if (ref.read(isProProvider)) return null;
    final count = await ref.read(repositoryProvider).countPeople();
    return (FreeLimits.people - count).clamp(0, FreeLimits.people);
  }

  /// 새 사람을 한 명 더 등록해도 되는지. 한도가 찼으면 결제 화면을 띄우고,
  /// 그 자리에서 구매하면 true(바로 이어서 저장), 닫으면 false.
  static Future<bool> canAddNewPerson(BuildContext context, WidgetRef ref) async {
    final remaining = await remainingPeople(ref);
    if (remaining == null || remaining > 0) return true;
    if (!context.mounted) return false;
    return showPaywall(context, ref,
        reason: '무료 버전은 ${FreeLimits.people}명까지 등록할 수 있어요.');
  }

  /// 장부 가져오기의 사람 한도. 프로면 null(제한 없음).
  static int? importPeopleLimit(WidgetRef ref) =>
      ref.read(isProProvider) ? null : FreeLimits.people;
}

/// 화면에 '무료로 n명 더 적을 수 있어요'를 보여주기 위한 남은 인원. 프로면 null.
final remainingPeopleProvider = FutureProvider<int?>((ref) async {
  ref.watch(dbVersionProvider);
  if (ref.watch(isProProvider)) return null;
  final count = await ref.watch(repositoryProvider).countPeople();
  return (FreeLimits.people - count).clamp(0, FreeLimits.people);
});
