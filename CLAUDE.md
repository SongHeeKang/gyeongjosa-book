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

- 단계별 요청문(기획서)은 `docs/`의 `경조사비 장부 앱 기획서 & Claude Code 개발 요청문 (3).md`에 있다(파일이 여러 개면 숫자가 가장 큰 것이 최신). 공개 저장소이므로 이 파일은 커밋하지 않는다(.gitignore). Claude Docs 링크는 VS Code에서 읽을 수 없으니 이 파일을 본다.
- 앱 이름: 경조사 장부 / 패키지: com.heekangsong.gyeongjosa
- DB 스키마 변경 시 `lib/data/database_helper.dart`의 `_dbVersion`을 올리고 `_migrations`에 단계를 추가한다. 기존 데이터를 지우는 마이그레이션은 금지.
- 무료 한도: 사람 30명, 내 행사 1개. CSV 내보내기와 관계별·연도별 차트는 프로 전용 (`lib/services/limits.dart`).
- 접수 모드와 장부 보내기는 무료·무제한이고, 접수 명단은 people에 넣지 않는다. 접수 중에는 결제 화면을 띄우지 않는다. 받은 장부를 가져올 때만 사람 30명 한도를 적용한다(넘으면 안내 후 결제 화면, 파일로 나중에 마저 가져오기).
- 이미 입력한 기록의 보기·수정·삭제는 한도와 상관없이 항상 허용.
- **Google Play 업로드 전 필수:** 설정의 테스트 도구(isPro 켜기/끄기 등)를 없앤다. `lib/services/app_config.dart`의 `testBuild`를 `false`로 바꾸면 APK·AAB에서 사라진다. 사용자가 출시·AAB·Play Console 업로드를 언급하면 먼저 이 작업을 하자고 요청할 것. `testBuild`가 `true`이면 `flutter build appbundle`은 일부러 실패한다. 이때 테스트 메뉴의 '더미데이터 추가'(`lib/data/dummy_data.dart`, 저장소의 더미 함수)도 사용자에게 알리고 코드째 지운다.
- Google 드라이브 백업용 OAuth 클라이언트는 'gyeongjosa-book debug'만 등록돼 있다. 8단계 빌드가 끝나면 업로드 키 SHA-1을 알려주고 'gyeongjosa-book upload' 추가를, 첫 AAB 업로드 뒤에는 Play Console 앱 무결성 → 앱 서명 키 인증서 SHA-1로 'gyeongjosa-book play' 추가를 안내한다.
- 화면별 도움말: 내용은 `lib/widgets/screen_coach.dart`의 `CoachScreen`, 모양은 `coach_mark.dart`. 새 자리는 `CoachTarget`으로 감싼다. 자동 표시는 화면별로 한 번이고, 접수 화면은 첫 저장 전에만 띄운다. 한 화면의 설명은 최대 3개이고, 설명이 적힌 항목이 모여 있으면 하나로 묶는다.
- 안드로이드 설정의 '데이터 삭제'는 `manageSpaceActivity`로 안내 화면(`lib/screens/manage_space_screen.dart`)을 연다. 앱 본체와 다른 Flutter 엔진에서 돌므로 DB는 `DatabaseHelper.separateConnection()`으로 연다.
- 자동 백업: 기록이 바뀌면(`dbVersionProvider`) 5초 뒤 Download/경조사장부/에 저장한다(`lib/services/auto_backup_service.dart`, `DownloadBackup.kt`). 빈 장부로는 백업하지 않고, 이번 앱 데이터에서 만든 파일만 덮어쓴다. Android 10 이상에서만 동작한다.
- 인앱 상품 ID: `pro_lifetime` (일회성 제품, 4,900원).
- 알림은 정확한 알람 권한 없이 일반 예약 알림(inexactAllowWhileIdle)만 사용.

## 디자인 (A 클린 화이트 + 아이콘 1)

- 색 · 글자 · 간격은 `lib/theme/app_theme.dart`(AppColors / AppText / AppSpacing)만 사용. 화면에 색 코드를 직접 쓰지 않는다.
- 카드 박스 · 그림자 대신 1px 구분선(AppDivider)으로 섹션을 나눈다. 좌우 여백 24, 섹션 간격 28.
- 금액: 받은 돈 '+50,000원' 포인트색, 보낸 돈 '−50,000원' 기본 글자색 (`signedWon`).
- 글꼴은 assets/fonts의 Noto Sans KR(400/500/700). 하단 메뉴 아이콘은 assets/icons의 SVG를 SvgTheme(currentColor)로 칠한다 (colorFilter 금지).
