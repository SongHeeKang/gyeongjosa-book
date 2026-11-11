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

  /// 내 행사를 하나 더 만들어도 되는지 (두 번째부터 결제 화면).
  /// 내 행사 탭, 받은 명단 직접 입력의 '바로 만들기', 장부 가져오기 · 내 장부로 옮기기의
  /// '새로 만들기'가 모두 이것을 거친다. 남의 행사(일정)와 접수 장부는 세지 않는다.
  static Future<bool> canCreateMyEvent(BuildContext context, WidgetRef ref) async {
    if (ref.read(isProProvider)) return true;
    final count = await ref.read(repositoryProvider).countMyEvents();
    if (count < FreeLimits.myEvents) return true;
    if (!context.mounted) return false;
    return showPaywall(context, ref,
        reason: '무료 버전은 내 행사를 ${FreeLimits.myEvents}개까지 만들 수 있어요.');
  }

  /// CSV 내보내기 · 상세 차트처럼 프로 전용 기능을 눌렀을 때
  static Future<bool> canUseProFeature(BuildContext context, WidgetRef ref,
      {required String reason}) async {
    if (ref.read(isProProvider)) return true;
    return showPaywall(context, ref, reason: reason);
  }

  /// 장부 가져오기의 사람 한도. 프로면 null(제한 없음).
  static int? importPeopleLimit(WidgetRef ref) =>
      ref.read(isProProvider) ? null : FreeLimits.people;
}

/// 테스트 메뉴에서 보는 한도 상태: 사람 수, 내 행사 수, isPro와 그 근거
class LimitStatus {
  const LimitStatus({
    required this.people,
    required this.myEvents,
    required this.isPro,
    required this.basis,
  });
  final int people;
  final int myEvents;
  final bool isPro;

  /// '테스트 스위치' · 'Google Play 구매' · '구매 없음'
  final String basis;

  String get summary => [
        '사람 $people명 / 무료 ${FreeLimits.people}명',
        '내 행사 $myEvents개 / 무료 ${FreeLimits.myEvents}개',
        'isPro ${isPro ? '켜짐' : '꺼짐'} (근거: $basis)',
      ].join('\n');
}

final limitStatusProvider = FutureProvider<LimitStatus>((ref) async {
  ref.watch(dbVersionProvider);
  final pro = ref.watch(proProvider);
  final repo = ref.watch(repositoryProvider);
  return LimitStatus(
    people: await repo.countPeople(),
    myEvents: await repo.countMyEvents(),
    isPro: pro.isPro,
    basis: pro.devOverride != null
        ? '테스트 스위치'
        : (pro.purchased ? 'Google Play 구매' : '구매 없음'),
  );
});

/// 화면에 '무료로 n명 더 적을 수 있어요'를 보여주기 위한 남은 인원. 프로면 null.
final remainingPeopleProvider = FutureProvider<int?>((ref) async {
  ref.watch(dbVersionProvider);
  if (ref.watch(isProProvider)) return null;
  final count = await ref.watch(repositoryProvider).countPeople();
  return (FreeLimits.people - count).clamp(0, FreeLimits.people);
});
