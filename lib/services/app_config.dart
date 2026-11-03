/// 출시 전에 직접 채워 넣어야 하는 값들.
class AppConfig {
  /// Play 콘솔 일회성 제품 ID
  static const proProductId = 'pro_lifetime';

  /// 상품 정보를 못 불러올 때 보여줄 가격
  static const proFallbackPrice = '4,900원';

  /// TODO(출시 전): Notion 또는 GitHub Pages에 올린 개인정보처리방침 주소로 바꾸세요.
  static const privacyPolicyUrl =
      'https://github.com/SongHeeKang/gyeongjosa-book/blob/main/PRIVACY.md';

  /// TODO(출시 전): 문의 받을 이메일 주소로 바꾸세요.
  static const supportEmail = 'support@example.com';
}
