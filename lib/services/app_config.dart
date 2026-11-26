import 'package:flutter/foundation.dart';

/// 홈 요약 카드의 백업 아이콘 · 백업 안내 선택창, 첫 실행 가이드의 백업 장을 보여줄지.
/// v1에서는 숨긴다(추가 X). 코드는 남겨 두었으니 true로 바꾸면 다시 보인다.
const kShowHomeBackup = false;

/// 출시 전에 직접 채워 넣어야 하는 값들.
class AppConfig {
  /// 출시용(2026-11-26): false. 릴리스 APK · AAB에는 설정의 테스트 메뉴가 나오지 않는다.
  /// (flutter run · debug APK에서는 [devToolsEnabled]로 계속 보인다.)
  /// true로 바꾸면 테스트 메뉴가 릴리스에도 나오고, 'flutter build appbundle'은 일부러 실패한다
  /// (android/app/build.gradle.kts). true면 받은 사람 누구나 프로를 공짜로 켤 수 있으니 출시에는 쓰지 않는다.
  static const testBuild = false;

  /// 설정 화면의 테스트 도구(isPro 켜기/끄기 등)를 쓸 수 있는지.
  /// flutter run에서는 항상 쓸 수 있고, APK에서는 [testBuild]가 true일 때만 쓸 수 있다.
  static const devToolsEnabled = kDebugMode || testBuild;

  /// Play 콘솔 일회성 제품 ID
  static const proProductId = 'pro_lifetime';

  /// Play 스토어 앱 주소 (패키지 이름으로 만든다)
  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.heekangsong.gyeongjosa';

  /// 상품 정보를 못 불러올 때 보여줄 가격
  static const proFallbackPrice = '4,900원';

  /// TODO(출시 전): Notion 또는 GitHub Pages에 올린 개인정보처리방침 주소로 바꾸세요.
  static const privacyPolicyUrl =
      'https://github.com/SongHeeKang/gyeongjosa-book/blob/main/PRIVACY.md';

  /// TODO(출시 전): 문의 받을 이메일 주소로 바꾸세요.
  static const supportEmail = 'support@example.com';
}
