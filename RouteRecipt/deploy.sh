#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

echo "📍 deploy.sh 실행 경로: $SCRIPT_DIR"
echo "📍 사용 .env 경로: $ENV_FILE"

chmod +x "$SCRIPT_DIR/switch-nginx.sh"

# ===============================
# Podman 경로 판별
# ===============================
if command -v podman >/dev/null 2>&1; then
  PODMAN=(podman)
else
  PODMAN=(/mnt/c/Program\ Files/RedHat/Podman/podman.exe)
fi

echo "🧩 사용 podman: ${PODMAN[*]}"

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
# AI / Cloudflare 보장
# ===============================
"${PODMAN[@]}" compose up -d "$AI_SERVICE" "$CF_SERVICE"

# ===============================
# 활성 Blue / Green 판별
# ===============================
if "${PODMAN[@]}" ps --format "{{.Names}}" | grep -qx "$BLUE_CONTAINER"; then
  ACTIVE_CONTAINER="$BLUE_CONTAINER"
  INACTIVE_SERVICE="$GREEN_SERVICE"
  INACTIVE_CONTAINER="$GREEN_CONTAINER"
else
  ACTIVE_CONTAINER="$GREEN_CONTAINER"
  INACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
fi

echo "현재 활성 컨테이너: $ACTIVE_CONTAINER"
echo "다음 배포 대상 컨테이너: $INACTIVE_CONTAINER"

# ===============================
# 이미지 빌드
# ===============================
"${PODMAN[@]}" compose build --no-cache "$INACTIVE_SERVICE"

# ===============================
# 컨테이너 강제 재생성 (🔥 핵심 수정)
# ===============================
"${PODMAN[@]}" compose up -d \
  --no-deps \
  --force-recreate \
  "$INACTIVE_SERVICE"

# ===============================
# 헬스체크
# ===============================
echo "🩺 헬스체크 확인 중..."
for i in {1..30}; do
  if "${PODMAN[@]}" exec "$INACTIVE_CONTAINER" \
      curl -sf http://localhost:8090/health | grep -q '"status":"up"'; then
    echo "✅ 헬스체크 통과"
    break
  fi
  sleep 2
done

# ===============================
# Nginx 전환
# ===============================
TARGET_COLOR="${INACTIVE_SERVICE#springboot-}"
"$SCRIPT_DIR/switch-nginx.sh" "$TARGET_COLOR"

# ===============================
# 기존 컨테이너 종료
# ===============================
"${PODMAN[@]}" stop "$ACTIVE_CONTAINER"

echo "🎉 RouteRecipt 무중단 배포 완료"
