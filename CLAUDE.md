# 경조사 장부 — 프로젝트 규칙

- 나는 개발 비전공자야. 작업이 끝나면 무엇을 바꿨는지, 내가 폰에서 무엇을 확인하면 되는지 한국어로 짧게 설명해줘.
- Android 전용 앱. 모든 화면 문구는 한국어.
- 서버 없음. 데이터는 sqflite로 기기에만 저장.
- 상태 관리는 flutter_riverpod.
- 폴더 구조: lib/models, lib/data, lib/screens, lib/widgets, lib/services.
- 금액은 정수(원) 저장, 화면에는 50,000원 형식으로 표시.
- 글자 크기는 넉넉하게, 버튼은 크게 (40~60대 사용자 고려).
- 변경할 때마다 flutter analyze를 돌려 경고 없이 마무리.
- 각 단계가 끝나면 flutter analyze 통과 확인 후, 한국어 커밋 메시지로 커밋하고 push한다.

## 참고 (구현 메모)

- 앱 이름: 경조사 장부 / 패키지: com.heekangsong.gyeongjosa
- DB 스키마 변경 시 `lib/data/database_helper.dart`의 `_dbVersion`을 올리고 `_migrations`에 단계를 추가한다. 기존 데이터를 지우는 마이그레이션은 금지.
- 무료 한도: 사람 30명, 내 행사 장부 1개. CSV 내보내기와 관계별·연도별 차트는 프로 전용 (`lib/services/limits.dart`).
- 이미 입력한 기록의 보기·수정·삭제는 한도와 상관없이 항상 허용.
- 인앱 상품 ID: `pro_lifetime` (일회성 제품, 4,900원).
- 알림은 정확한 알람 권한 없이 일반 예약 알림(inexactAllowWhileIdle)만 사용.
