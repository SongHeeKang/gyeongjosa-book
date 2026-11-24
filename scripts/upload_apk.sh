#!/bin/bash
# 폰용 APK 올리기 (macOS)
#   flutter build apk --release → 경조사장부_{버전}_{빌드번호}_{날짜시간}.apk 로 이름 바꾸기
#   → Synology Drive 동기화 폴더에 복사 → 그 폴더의 경조사장부_*.apk 는 최근 5개만 남기기
# 동기화 폴더 경로는 프로젝트 루트 .env.local 의 APK_UPLOAD_DIR 에서 읽는다 (git에 올리지 않음).
# 빌드 번호(pubspec.yaml 의 version: x.y.z+N 의 N)는 실행할 때마다 1씩 올라간다(빌드가 성공했을 때만 저장).
# 서명: android/app/build.gradle.kts 의 release 설정 그대로(지금은 이 맥의 ~/.android/debug.keystore).
#        같은 키로 서명해야 폰에 덮어 설치된다. 키 지문(SHA-256)을 매번 출력하니 바뀌면 바로 알 수 있다.

set -uo pipefail

KEEP=5
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

step() { printf '\n▶ [%s/5] %s\n' "$1" "$2"; }
fail() { printf '\n✖ 실패 — [%s단계] %s\n' "$1" "$2" >&2; exit 1; }

# VS Code 작업에서는 로그인 셸 PATH가 없을 수 있어 flutter 위치를 찾아 둔다
FLUTTER="$(command -v flutter || true)"
for c in "$HOME/fvm/default/bin/flutter" "$HOME/Setup/flutter/bin/flutter" /opt/homebrew/bin/flutter /usr/local/bin/flutter; do
  [ -n "$FLUTTER" ] && break
  [ -x "$c" ] && FLUTTER="$c"
done

# ── 1. 설정 읽기 · 버전 정하기 ─────────────────────────────
step 1 "설정 읽기 · 빌드 번호 올리기"
[ -n "$FLUTTER" ] || fail 1 "flutter 명령을 찾을 수 없어요."
[ -f .env.local ] || fail 1 ".env.local 파일이 없어요. 프로젝트 루트에 APK_UPLOAD_DIR=동기화폴더경로 한 줄을 넣어 주세요."
APK_UPLOAD_DIR="$(grep -E '^APK_UPLOAD_DIR=' .env.local | tail -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
[ -n "$APK_UPLOAD_DIR" ] || fail 1 ".env.local 에 APK_UPLOAD_DIR 값이 없어요."
APK_UPLOAD_DIR="${APK_UPLOAD_DIR/#\~/$HOME}"

VERSION_LINE="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[[:space:]]*$' pubspec.yaml)"
[ -n "$VERSION_LINE" ] || fail 1 "pubspec.yaml 의 version 형식(예: 1.0.0+3)을 읽지 못했어요."
VERSION="$(echo "$VERSION_LINE" | sed -E 's/^version:[[:space:]]*//; s/[[:space:]]*$//')"
BUILD_NAME="${VERSION%%+*}"
BUILD_NUMBER="$(( ${VERSION##*+} + 1 ))"
echo "버전 $BUILD_NAME, 빌드 번호 ${VERSION##*+} → $BUILD_NUMBER"
echo "동기화 폴더: $APK_UPLOAD_DIR"

# ── 2. 빌드 ─────────────────────────────────────────────
step 2 "flutter build apk --release"
"$FLUTTER" build apk --release --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER" \
  || fail 2 "빌드가 실패했어요. 위 빌드 로그를 확인해 주세요. (빌드 번호는 올리지 않았어요)"
SRC="build/app/outputs/flutter-apk/app-release.apk"
[ -f "$SRC" ] || fail 2 "빌드 결과 파일($SRC)이 없어요."
# 빌드가 성공했을 때만 pubspec.yaml 의 빌드 번호를 올린다 (형식 x.y.z+N 유지)
sed -i '' -E "s/^version:[[:space:]]*.*/version: ${BUILD_NAME}+${BUILD_NUMBER}/" pubspec.yaml \
  || fail 2 "pubspec.yaml 빌드 번호를 저장하지 못했어요."

# ── 3. 이름 바꾸기 · 서명 확인 ──────────────────────────────
step 3 "파일 이름 바꾸기 · 서명 키 확인"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_NAME="경조사장부_${BUILD_NAME}_${BUILD_NUMBER}_${STAMP}.apk"
OUT="build/app/outputs/flutter-apk/$OUT_NAME"
cp "$SRC" "$OUT" || fail 3 "APK 이름을 바꾸지 못했어요."
echo "만든 파일: $OUT"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
APKSIGNER="$(ls -d "$SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"
if [ -n "$APKSIGNER" ]; then
  SHA="$("$APKSIGNER" verify --print-certs "$OUT" 2>/dev/null | grep -m1 'SHA-256 digest' | sed 's/.*: //')"
  echo "서명 키 SHA-256: ${SHA:-확인 못 함}"
else
  echo "서명 키: apksigner가 없어 확인하지 못했어요"
fi

# ── 4. 동기화 폴더로 복사 ───────────────────────────────────
step 4 "동기화 폴더로 복사"
if [ ! -d "$APK_UPLOAD_DIR" ]; then
  printf '\n✖ 실패 — [4단계] 동기화 폴더를 찾을 수 없어요. Synology Drive Client 설정을 확인해 주세요\n' >&2
  echo "  찾은 경로: $APK_UPLOAD_DIR" >&2
  echo "  APK는 build 폴더에 남겨 두었어요: $ROOT/$OUT" >&2
  exit 1
fi
cp "$OUT" "$APK_UPLOAD_DIR/$OUT_NAME" || fail 4 "동기화 폴더에 복사하지 못했어요. (APK는 $OUT 에 있어요)"
cmp -s "$OUT" "$APK_UPLOAD_DIR/$OUT_NAME" || fail 4 "복사한 파일이 원본과 달라요. 다시 실행해 주세요."

# ── 5. 오래된 APK 정리 (경조사장부_*.apk 만, 최근 5개 남김) ──────
step 5 "오래된 APK 정리 (최근 ${KEEP}개만 남김)"
OLD="$(ls -t "$APK_UPLOAD_DIR"/경조사장부_*.apk 2>/dev/null | tail -n +$((KEEP + 1)))"
if [ -n "$OLD" ]; then
  while IFS= read -r f; do
    rm -f -- "$f" && echo "지움: $(basename "$f")"
  done <<< "$OLD"
else
  echo "지울 파일 없음"
fi
# build 폴더에 쌓이는 이름 바꾼 사본도 최근 5개만
ls -t build/app/outputs/flutter-apk/경조사장부_*.apk 2>/dev/null | tail -n +$((KEEP + 1)) | while IFS= read -r f; do rm -f -- "$f"; done

printf '\n✔ 동기화 폴더에 올렸어요: %s (Synology Drive가 NAS로 올려요)\n' "$OUT_NAME"
