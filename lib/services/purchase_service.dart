import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'app_config.dart';
import 'pro_service.dart';

class PurchaseUiState {
  final bool available;
  final bool busy;
  final ProductDetails? product;

  /// 화면에 한 번 보여줄 안내 문구 (스낵바)
  final String? message;
  final int messageId;

  const PurchaseUiState({
    this.available = false,
    this.busy = false,
    this.product,
    this.message,
    this.messageId = 0,
  });

  String get priceText => product?.price ?? AppConfig.proFallbackPrice;

  PurchaseUiState copyWith({
    bool? available,
    bool? busy,
    ProductDetails? product,
    String? message,
  }) =>
      PurchaseUiState(
        available: available ?? this.available,
        busy: busy ?? this.busy,
        product: product ?? this.product,
        message: message ?? this.message,
        messageId: message != null ? messageId + 1 : messageId,
      );
}

/// Google Play 결제 (in_app_purchase) 처리.
/// - 앱 시작 때 [init]으로 구매 내역을 확인해 isPro를 갱신
/// - 결제 성공 시 completePurchase(= acknowledge) 처리
class PurchaseController extends Notifier<PurchaseUiState> {
  StreamSubscription<List<PurchaseDetails>>? _sub;
  InAppPurchase get _iap => InAppPurchase.instance;

  @override
  PurchaseUiState build() {
    ref.onDispose(() => _sub?.cancel());
    return const PurchaseUiState();
  }

  Future<void> init() async {
    try {
      _sub ??= _iap.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) => _say('결제 처리 중 오류가 났어요: $e', busy: false),
      );
      final available = await _iap.isAvailable();
      state = state.copyWith(available: available);
      if (!available) return;

      final response =
          await _iap.queryProductDetails({AppConfig.proProductId});
      if (response.productDetails.isNotEmpty) {
        state = state.copyWith(product: response.productDetails.first);
      }
      await _refreshFromPastPurchases();
    } catch (e) {
      debugPrint('결제 초기화 실패: $e');
    }
  }

  /// Google Play에 남아 있는 구매 내역을 직접 조회해 isPro를 맞춘다.
  /// 조회 자체가 실패하면(오프라인 등) 기존 값을 유지한다.
  Future<bool?> _refreshFromPastPurchases() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final addition =
        _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final result = await addition.queryPastPurchases();
    if (result.error != null) return null;

    var owned = false;
    for (final p in result.pastPurchases) {
      if (p.productID != AppConfig.proProductId) continue;
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        owned = true;
      }
      // 아직 확인(acknowledge)되지 않은 구매가 있으면 처리 (3일 안에 안 하면 자동 환불됨)
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
    await ref.read(proProvider.notifier).setPurchased(owned);
    return owned;
  }

  Future<void> buy() async {
    if (!state.available) {
      _say('지금은 결제를 사용할 수 없어요. Play 스토어에서 설치한 앱인지 확인해 주세요.');
      return;
    }
    var product = state.product;
    if (product == null) {
      final response =
          await _iap.queryProductDetails({AppConfig.proProductId});
      if (response.productDetails.isEmpty) {
        _say('상품 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
        return;
      }
      product = response.productDetails.first;
      state = state.copyWith(product: product);
    }
    state = state.copyWith(busy: true);
    try {
      await _iap.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product));
    } catch (e) {
      _say('결제를 시작하지 못했어요: $e', busy: false);
    }
  }

  Future<void> restore() async {
    if (!state.available) {
      _say('지금은 Play 스토어에 연결할 수 없어요. 인터넷 연결을 확인해 주세요.');
      return;
    }
    state = state.copyWith(busy: true);
    try {
      final owned = await _refreshFromPastPurchases();
      if (owned == true) {
        _say('구매를 복원했어요. 프로 기능을 모두 쓸 수 있어요.', busy: false);
      } else if (owned == false) {
        _say('이 Google 계정으로 구매한 내역을 찾지 못했어요.', busy: false);
      } else {
        _say('구매 내역을 확인하지 못했어요. 잠시 후 다시 시도해 주세요.', busy: false);
      }
    } catch (e) {
      _say('구매 복원 중 오류가 났어요: $e', busy: false);
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID != AppConfig.proProductId) {
        if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        continue;
      }
      switch (p.status) {
        case PurchaseStatus.pending:
          _say('결제를 처리하고 있어요. 완료되면 자동으로 프로가 켜져요.');
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await ref.read(proProvider.notifier).setPurchased(true);
          _say('프로가 켜졌어요. 감사합니다!', busy: false);
        case PurchaseStatus.error:
          _say('결제에 실패했어요. ${p.error?.message ?? ''}'.trim(), busy: false);
        case PurchaseStatus.canceled:
          state = state.copyWith(busy: false);
      }
      // 결제 성공 후 반드시 확인(acknowledge) 처리
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  void _say(String message, {bool? busy}) {
    state = state.copyWith(message: message, busy: busy);
  }
}

final purchaseProvider =
    NotifierProvider<PurchaseController, PurchaseUiState>(
        PurchaseController.new);
