#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🚀 RouteRecipt CI 무중단 배포 시작 (Linux Runner)"

PODMAN=(podman)

PROJECT="routerecipt"

BLUE_SERVICE="springboot-blue"
GREEN_SERVICE="springboot-green"
AI_SERVICE="fastapi-ai"
CF_SERVICE="cloudflared"

BLUE_CONTAINER="${PROJECT}-springboot-blue"
GREEN_CONTAINER="${PROJECT}-springboot-green"

# ===============================
# AI / Cloudflare 보장
# ===============================
podman compose up -d "$AI_SERVICE" "$CF_SERVICE"

# ===============================
# 활성 색상 판별
# ===============================
if podman ps --format "{{.Names}}" | grep -qx "$BLUE_CONTAINER"; then
  ACTIVE="$BLUE_CONTAINER"
  INACTIVE_SERVICE="$GREEN_SERVICE"
  INACTIVE_CONTAINER="$GREEN_CONTAINER"
else
  ACTIVE="$GREEN_CONTAINER"
  INACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
fi

echo "▶ 배포 대상: $INACTIVE_CONTAINER"

# ===============================
# 빌드 & 재생성
# ===============================
podman compose build --no-cache "$INACTIVE_SERVICE"
podman compose up -d --no-deps --force-recreate "$INACTIVE_SERVICE"

# ===============================
# 헬스체크
# ===============================
for i in {1..30}; do
  if podman exec "$INACTIVE_CONTAINER" curl -sf http://localhost:8090/health | grep -q up; then
    echo "✅ 헬스체크 통과"
    break
  fi
  sleep 2
done

# ===============================
# Nginx 전환
# ===============================
./switch-nginx.sh "${INACTIVE_SERVICE#springboot-}"

# ===============================
# 기존 컨테이너 종료
# ===============================
podman stop "$ACTIVE"

echo "🎉 CI 배포 완료"
