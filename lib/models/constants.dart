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

  /// 금액 버튼 8개. 손이 위치를 외우도록 순서를 바꾸지 않는다.
  static const amounts = [
    50000,
    100000,
    150000,
    200000,
    250000,
    300000,
    500000,
    1000000,
  ];

  static String methodLabel(String method) =>
      method == transfer ? '계좌이체' : '현금';
}

/// 테스트 전용 더미 데이터 표시. 메모에 이 값이 있는 사람 · 행사만 한꺼번에 지운다.
const dummyDataMarker = '[테스트 더미 데이터]';

class Direction {
  static const sent = '보냄';
  static const received = '받음';
}
