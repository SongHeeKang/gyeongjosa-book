import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';
import 'settings_service.dart';

class ProState {
  /// Google Play에서 확인된 구매 여부 (기기에 캐시)
  final bool purchased;

  /// 테스트 도구 전용 스위치 (null이면 실제 구매 여부 사용)
  final bool? devOverride;

  const ProState({required this.purchased, this.devOverride});

  bool get isPro => devOverride ?? purchased;
}

class ProNotifier extends Notifier<ProState> {
  @override
  ProState build() {
    final prefs = ref.watch(prefsProvider);
    return ProState(
      purchased: prefs.getBool(PrefKeys.proPurchased) ?? false,
      devOverride: AppConfig.devToolsEnabled ? prefs.getBool(PrefKeys.devProOverride) : null,
    );
  }

  Future<void> setPurchased(bool value) async {
    await ref.read(prefsProvider).setBool(PrefKeys.proPurchased, value);
    state = ProState(purchased: value, devOverride: state.devOverride);
  }

  /// 테스트 도구에서만 쓰는 isPro 켜기/끄기
  Future<void> setDevOverride(bool? value) async {
    if (!AppConfig.devToolsEnabled) return;
    final prefs = ref.read(prefsProvider);
    if (value == null) {
      await prefs.remove(PrefKeys.devProOverride);
    } else {
      await prefs.setBool(PrefKeys.devProOverride, value);
    }
    state = ProState(purchased: state.purchased, devOverride: value);
  }
}

final proProvider = NotifierProvider<ProNotifier, ProState>(ProNotifier.new);

/// 화면에서 프로 여부만 필요할 때
final isProProvider = Provider<bool>((ref) => ref.watch(proProvider).isPro);
