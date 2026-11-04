/// 화면과 DB에서 공통으로 쓰는 선택지 목록.
class Relations {
  static const all = ['가족', '친구', '회사', '지인', '기타'];
}

class EventTypes {
  static const all = ['결혼', '장례', '돌', '생일', '개업', '기타'];
}

class Methods {
  static const all = ['현금', '계좌', '선물'];
}

/// 접수 모드 기본값
class ReceptionDefaults {
  static const cash = '현금';
  static const transfer = '계좌';
  static const weddingSides = ['신랑측', '신부측'];

  /// 구분을 나누지 않는 행사
  static const noSide = '전체';

  /// 금액 버튼: 3만 · 5만 · 10만 · 20만
  static const amounts = [30000, 50000, 100000, 200000];

  static String methodLabel(String method) =>
      method == transfer ? '계좌이체' : '현금';
}

class Direction {
  static const sent = '보냄';
  static const received = '받음';
}
