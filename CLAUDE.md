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
- 무료 한도: 사람 50명(`kFreePeopleLimit`, 이 상수 하나만 바꾸면 문구까지 바뀜), 내 행사 1개. 관계별·연도별 차트만 프로 전용 (`lib/services/limits.dart`). 공유 · 다운로드(엑셀 .xlsx · 텍스트)는 무료: 홈(주고받은 내역) · 행사 탭(행사 장부 전체) · 행사 상세(그 행사) 오른쪽 위 [공유] [다운로드] 아이콘(사람 탭에는 없음). 기록이 없으면 회색. 받기 끝내기 화면의 [공유하기]도 같은 선택창. 만드는 코드는 `lib/services/export_service.dart` 한 곳(행사 텍스트는 `ledger_text_format.dart` 재사용), 아이콘 · 선택창은 `lib/widgets/share_download.dart`. 다운로드는 `FilePicker.saveFile`(권한 요청 없음). 보관/지우기 질문은 다른 사람 행사 상세에서 공유한 뒤에만(행사 탭 공유 뒤엔 묻지 않음). 숨긴 [정보] 시트에 파일 종류 · 형식 버전(1)을 넣는다. 설정의 CSV 내보내기는 없앴다.
- 행사는 만들 때 '누구 행사예요?'를 한 번 고른다(`reception_form_screen.dart`). 행사 탭 묶음 제목의 [+ 추가]는 그 종류로 골라 둔 채 연다(`openCreateEventOf`, 내 행사는 누르는 순간 한도 검사). 행사 0개 · 홈 일정 없음은 같은 `EmptyView`. 내 행사는 events + people/records('받음'), 다른 사람 행사는 receptions + reception_entries에만 저장하고 사람 탭 · 통계 · 한도에 넣지 않는다. 다른 사람 행사를 적는 중에는 결제 화면을 띄우지 않는다. 내 행사 한도는 [내 행사]를 고르는 순간 · [내 행사로 바꾸기]를 누르는 순간 검사한다.
- 장부 보내기는 글자만(파일 없음, 무료). 보내는 글과 붙여넣어 가져오기는 `lib/services/ledger_text_format.dart` 한 곳에서 같은 형식을 쓴다(형식을 바꾸면 `test/ledger_text_test.dart` 왕복 테스트도). 100명(`kShareChunkSize`)씩 나눠 보낸다. share_plus에 subject를 넣지 않는다.
- 붙여넣어 가져오기만 사람 한도를 적용한다(넘으면 "N명 중 n명까지" 결제 화면, 같은 메시지로 나중에 마저). 같은 줄(행사 이름 · 날짜 · 이름 · 금액 · 구분)은 두 번 저장하지 않는다. 예전 JSON 장부 파일은 [예전 장부 파일 가져오기]로 읽기만 한다. 파일 연결(intent-filter)은 없앴다.
- 이미 입력한 기록의 보기·수정·삭제는 한도와 상관없이 항상 허용.
- **Google Play 업로드 전 필수:** 설정의 테스트 도구(isPro 켜기/끄기 등)를 없앤다. `lib/services/app_config.dart`의 `testBuild`를 `false`로 바꾸면 APK·AAB에서 사라진다. 사용자가 출시·AAB·Play Console 업로드를 언급하면 먼저 이 작업을 하자고 요청할 것. `testBuild`가 `true`이면 `flutter build appbundle`은 일부러 실패한다. 이때 테스트 메뉴의 '더미데이터 추가'(`lib/data/dummy_data.dart`, 저장소의 더미 함수)도 사용자에게 알리고 코드째 지운다.
- Google 드라이브 백업은 v1에서 뺐다(추가 W). Drive API · google_sign_in · OAuth 설정을 쓰지 않는다. 백업은 ① 다운로드 자동 백업(최근 7개) ② 안드로이드 자동 백업(allowBackup, backup_rules · data_extraction_rules에 DB · 설정 포함) ③ 백업 파일 → 공유창.
- 내 행사 한도: 버튼을 누르는 순간 `LimitService.canCreateMyEvent`, 저장 순간 `LimitService.saveMyEvent` + 저장소의 `maxMyEvents`(트랜잭션 안에서 다시 세어 넘으면 `MyEventLimitReached`). 내 행사를 만드는 새 입구를 만들면 둘 다 거치게 하고, 저장 버튼은 첫 await 전에 막는다(빠른 연속 누르기).
- 홈: 요약 줄 오른쪽 백업 아이콘(`lib/widgets/backup_guide.dart`, 7일 이내 초록 · 기록 있는데 없거나 30일 지나면 주황 점), '최근 6개월' 그래프는 통계 탭과 같은 `GroupedBarChart`(`lib/widgets/grouped_bar_chart.dart`).
- 화면별 도움말: 내용은 `lib/widgets/screen_coach.dart`의 `CoachScreen`, 모양은 `coach_mark.dart`. 새 자리는 `CoachTarget`으로 감싼다. 자동 표시는 화면별로 한 번이고, 접수 화면은 첫 저장 전에만 띄운다. 한 화면의 설명은 최대 3개이고, 설명이 적힌 항목이 모여 있으면 하나로 묶는다.
- 행사장 접수와 받은 명단 직접 입력의 금액칸 · 금액 버튼 · 최근 저장은 `lib/widgets/amount_pad.dart`의 공통 위젯을 쓴다. 식권 · 계좌 칩과 구분은 접수에만 있다.
- 안드로이드 설정의 '데이터 삭제'는 `manageSpaceActivity`로 안내 화면(`lib/screens/manage_space_screen.dart`)을 연다. 앱 본체와 다른 Flutter 엔진에서 돌므로 DB는 `DatabaseHelper.separateConnection()`으로 연다.
- 자동 백업: 기록이 바뀌면(`dbVersionProvider`) 5초 뒤 Download/경조사장부/에 저장한다(`lib/services/auto_backup_service.dart`, `DownloadBackup.kt`). 빈 장부로는 백업하지 않고, 이번 앱 데이터에서 만든 파일만 덮어쓴다. Android 10 이상에서만 동작한다.
- 자동화 테스트는 이 저장소 밖의 별도 프로젝트(AutoTest: Python + behave + Appium + Allure)에 있다. 주요 위젯은 `lib/widgets/test_id.dart`의 `TestId('이름', child: ...)`로 감싸 resource-id를 붙인다. 화면을 고칠 때 이 식별자를 지우거나 이름을 바꾸지 않는다(바꾸면 README 표와 시나리오도 함께 고친다). 자동화용 APK는 debug 빌드.
- 인앱 상품 ID: `pro_lifetime` (일회성 제품, 4,900원).
- 알림은 정확한 알람 권한 없이 일반 예약 알림(inexactAllowWhileIdle)만 사용. 앱을 켤 때 거절해도 스낵바 없음. 홈 일정 아래 '알림이 꺼져 있어요 · 켜기', 설정에 켜짐/꺼짐 + [설정 열기].
- 사람 탭 인원은 헤더가 아니라 칩 아래 제목 줄('전체 n명', 무료면 '· 무료 50명까지' + 막대).

## 디자인 (A 클린 화이트 + 아이콘 1)

- 색 · 글자 · 간격은 `lib/theme/app_theme.dart`(AppColors / AppText / AppSpacing)만 사용. 화면에 색 코드를 직접 쓰지 않는다.
- 카드 박스 · 그림자 대신 1px 구분선(AppDivider)으로 섹션을 나눈다. 좌우 여백 24, 섹션 간격 28.
- 금액: 받은 돈 '+50,000원' 파랑(`AppColors.received`), 보낸 돈 '−50,000원' 코랄(`AppColors.sent`, #D85A30). 그래프 보냄 막대도 코랄. 빨강(`error`)은 오류 · 경고 전용 (`signedWon`, `AppColors.amount`).
- 글꼴은 assets/fonts의 Noto Sans KR(400/500/700). 하단 메뉴 아이콘은 assets/icons의 SVG를 SvgTheme(currentColor)로 칠한다 (colorFilter 금지).
