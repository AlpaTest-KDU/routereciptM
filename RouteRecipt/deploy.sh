#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

echo "📍 deploy.sh 실행 경로: $SCRIPT_DIR"
echo "📍 사용 .env 경로: $ENV_FILE"

chmod +x "$SCRIPT_DIR/switch-nginx.sh"

PODMAN=(/mnt/c/Program\ Files/RedHat/Podman/podman.exe)

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
# 1️⃣ AI 서비스 보장
# ===============================
if ! "${PODMAN[@]}" ps --format "{{.Names}}" | grep -q "^${AI_CONTAINER}$"; then
  echo "▶ fastapi-ai 기동"
  "${PODMAN[@]}" compose up -d "$AI_SERVICE"
else
  echo "✔ fastapi-ai 이미 실행 중"
fi

# ===============================
# 2️⃣ Cloudflare Tunnel 보장
# ===============================
if ! "${PODMAN[@]}" ps --format "{{.Names}}" | grep -q "^${CF_CONTAINER}$"; then
  echo "▶ cloudflared 기동"
  "${PODMAN[@]}" compose up -d "$CF_SERVICE"
else
  echo "✔ cloudflared 이미 실행 중"
fi

# ===============================
# 3️⃣ 현재 활성 Blue / Green 판별
# ===============================
if "${PODMAN[@]}" ps --format "{{.Names}}" | grep -q "^${BLUE_CONTAINER}$"; then
  ACTIVE_CONTAINER="$BLUE_CONTAINER"
  ACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_SERVICE="$GREEN_SERVICE"
  INACTIVE_CONTAINER="$GREEN_CONTAINER"
elif "${PODMAN[@]}" ps --format "{{.Names}}" | grep -q "^${GREEN_CONTAINER}$"; then
  ACTIVE_CONTAINER="$GREEN_CONTAINER"
  ACTIVE_SERVICE="$GREEN_SERVICE"
  INACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
else
  echo "⚠️ 최초 배포 (blue 선택)"
  ACTIVE_CONTAINER=""
  INACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
fi

echo "현재 활성 컨테이너: ${ACTIVE_CONTAINER:-없음}"
echo "다음 배포 대상 컨테이너: $INACTIVE_CONTAINER"

# ===============================
# 4️⃣ Spring Boot 이미지 빌드
# ===============================
"${PODMAN[@]}" compose build --no-cache "$INACTIVE_SERVICE"

# ===============================
# 5️⃣ 비활성 컨테이너 재생성
# ===============================
"${PODMAN[@]}" rm -f "$INACTIVE_CONTAINER" 2>/dev/null || true
"${PODMAN[@]}" compose up -d "$INACTIVE_SERVICE"

# ===============================
# 6️⃣ 헬스체크
# ===============================
echo "🩺 헬스체크 확인 중..."
for i in {1..30}; do
  if "${PODMAN[@]}" exec "$INACTIVE_CONTAINER" \
     curl -sf http://localhost:8090/health | grep -q '"status":"up"'; then
    echo "✅ 헬스체크 통과"
    break
  fi
  echo "⏳ 대기 중... ($i)"
  sleep 2
done

# ===============================
# 7️⃣ Nginx 트래픽 전환
# ===============================
TARGET_COLOR=$(echo "$INACTIVE_SERVICE" | sed 's/springboot-//')
"$SCRIPT_DIR/switch-nginx.sh" "$TARGET_COLOR"

# ===============================
# 8️⃣ 기존 컨테이너 종료
# ===============================
if [[ -n "$ACTIVE_CONTAINER" ]]; then
  "${PODMAN[@]}" stop "$ACTIVE_CONTAINER"
fi

echo "🎉 무중단 배포 완료"
