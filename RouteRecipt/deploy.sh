#!/bin/bash
set -e

# ===============================
# 0️⃣ 기본 경로 설정
# ===============================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

echo "📍 deploy.sh 실행 경로: $SCRIPT_DIR"
echo "📍 사용 .env 경로: $ENV_FILE"

chmod +x "$SCRIPT_DIR/switch-nginx.sh"

# ===============================
# 1️⃣ Podman 경로 자동 판별
# ===============================
if command -v podman >/dev/null 2>&1; then
  PODMAN=(podman)
else
  PODMAN=(/mnt/c/Program\ Files/RedHat/Podman/podman.exe)
fi

echo "🧩 사용 podman: ${PODMAN[*]}"

# ===============================
# 2️⃣ 서비스 / 컨테이너 이름
# ===============================
PROJECT="routerecipt"

BLUE_SERVICE="springboot-blue"
GREEN_SERVICE="springboot-green"
AI_SERVICE="fastapi-ai"
CF_SERVICE="cloudflared"

BLUE_CONTAINER="${PROJECT}-springboot-blue"
GREEN_CONTAINER="${PROJECT}-springboot-green"
AI_CONTAINER="${PROJECT}-fastapi-ai"
CF_CONTAINER="${PROJECT}-cloudflared"

echo "🚀 RouteRecipt 무중단 배포 시작"

# ===============================
# 3️⃣ AI 서비스 보장
# ===============================
if ! "${PODMAN[@]}" ps --format "{{.Names}}" | grep -qx "$AI_CONTAINER"; then
  echo "▶ fastapi-ai 기동"
  "${PODMAN[@]}" compose up -d "$AI_SERVICE"
else
  echo "✔ fastapi-ai 이미 실행 중"
fi

# ===============================
# 4️⃣ Cloudflare Tunnel 보장
# ===============================
if ! "${PODMAN[@]}" ps --format "{{.Names}}" | grep -qx "$CF_CONTAINER"; then
  echo "▶ cloudflared 기동"
  "${PODMAN[@]}" compose up -d "$CF_SERVICE"
else
  echo "✔ cloudflared 이미 실행 중"
fi

# ===============================
# 5️⃣ 현재 활성 Blue / Green 판별
# ===============================
if "${PODMAN[@]}" ps --format "{{.Names}}" | grep -qx "$BLUE_CONTAINER"; then
  ACTIVE_CONTAINER="$BLUE_CONTAINER"
  ACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_SERVICE="$GREEN_SERVICE"
  INACTIVE_CONTAINER="$GREEN_CONTAINER"
elif "${PODMAN[@]}" ps --format "{{.Names}}" | grep -qx "$GREEN_CONTAINER"; then
  ACTIVE_CONTAINER="$GREEN_CONTAINER"
  ACTIVE_SERVICE="$GREEN_SERVICE"
  INACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
else
  echo "⚠️ 최초 배포 → blue 사용"
  ACTIVE_CONTAINER=""
  INACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
fi

echo "현재 활성 컨테이너: ${ACTIVE_CONTAINER:-없음}"
echo "다음 배포 대상 컨테이너: $INACTIVE_CONTAINER"

# ===============================
# 6️⃣ Spring Boot 이미지 빌드
# ===============================
echo "🔨 이미지 빌드: $INACTIVE_SERVICE"
"${PODMAN[@]}" compose build --no-cache "$INACTIVE_SERVICE"

# ===============================
# 7️⃣ 비활성 Spring 컨테이너만 재생성
# ===============================
echo "♻️ $INACTIVE_CONTAINER 재생성"
"${PODMAN[@]}" rm -f "$INACTIVE_CONTAINER" 2>/dev/null || true
"${PODMAN[@]}" compose up -d --no-deps "$INACTIVE_SERVICE"

# ===============================
# 8️⃣ 헬스체크
# ===============================
echo "🩺 헬스체크 확인 중..."
HEALTH_OK=false

for i in {1..30}; do
  if "${PODMAN[@]}" exec "$INACTIVE_CONTAINER" \
      curl -sf http://localhost:8090/health | grep -q '"status":"up"'; then
    echo "✅ 헬스체크 통과"
    HEALTH_OK=true
    break
  fi
  echo "⏳ 대기 중... ($i)"
  sleep 2
done

if [[ "$HEALTH_OK" != "true" ]]; then
  echo "❌ 헬스체크 실패 → 배포 중단"
  "${PODMAN[@]}" logs "$INACTIVE_CONTAINER" --tail 50 || true
  exit 1
fi

# ===============================
# 9️⃣ Nginx 트래픽 전환
# ===============================
TARGET_COLOR="${INACTIVE_SERVICE#springboot-}"
echo "🔀 Nginx 트래픽 전환 → $TARGET_COLOR"
"$SCRIPT_DIR/switch-nginx.sh" "$TARGET_COLOR"

# ===============================
# 🔟 기존 컨테이너 종료
# ===============================
if [[ -n "$ACTIVE_CONTAINER" ]]; then
  echo "🔁 기존 컨테이너 종료: $ACTIVE_CONTAINER"
  "${PODMAN[@]}" stop "$ACTIVE_CONTAINER"
else
  echo "ℹ️ 기존 활성 컨테이너 없음"
fi

echo "🎉 RouteRecipt 무중단 배포 완료"
