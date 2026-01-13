#!/bin/bash
set -e

echo "🚀 RouteRecipt CI 무중단 배포 시작"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ===============================
# Podman 존재 여부 확인만 수행
# ===============================
if ! command -v podman >/dev/null 2>&1; then
  echo "❌ podman이 설치되어 있지 않습니다."
  echo "👉 GitHub Actions workflow에서 podman을 먼저 설치하세요."
  exit 1
fi

echo "🧩 podman: $(podman --version)"

# ===============================
# 서비스 / 컨테이너 이름
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

# ===============================
# 인프라 보장 기동 (DB/Redis/Nginx/AI/CF)
# ===============================
echo "📦 인프라 서비스 기동"
podman compose up -d mariadb redis nginx fastapi-ai cloudflared

# ===============================
# 활성 Blue / Green 판별
# ===============================
if podman ps --format "{{.Names}}" | grep -qx "$BLUE_CONTAINER"; then
  ACTIVE_CONTAINER="$BLUE_CONTAINER"
  INACTIVE_SERVICE="$GREEN_SERVICE"
  INACTIVE_CONTAINER="$GREEN_CONTAINER"
elif podman ps --format "{{.Names}}" | grep -qx "$GREEN_CONTAINER"; then
  ACTIVE_CONTAINER="$GREEN_CONTAINER"
  INACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
else
  echo "⚠️ 최초 배포 → blue 선택"
  ACTIVE_CONTAINER=""
  INACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
fi

echo "현재 활성 컨테이너: ${ACTIVE_CONTAINER:-없음}"
echo "다음 배포 대상: $INACTIVE_CONTAINER"

# ===============================
# Spring 이미지 빌드
# ===============================
echo "🔨 Spring 이미지 빌드: $INACTIVE_SERVICE"
podman compose build --no-cache "$INACTIVE_SERVICE"

# ===============================
# 비활성 컨테이너 재기동
# ===============================
podman rm -f "$INACTIVE_CONTAINER" 2>/dev/null || true
podman compose up -d --no-deps "$INACTIVE_SERVICE"

# ===============================
# 헬스체크
# ===============================
echo "🩺 헬스체크"
for i in {1..30}; do
  if podman exec "$INACTIVE_CONTAINER" \
     curl -sf http://localhost:8090/health | grep -q '"status":"up"'; then
    echo "✅ 헬스체크 통과"
    break
  fi
  sleep 2
done

# ===============================
# Nginx 트래픽 전환
# ===============================
chmod +x switch-nginx.sh
./switch-nginx.sh "${INACTIVE_SERVICE#springboot-}"

# ===============================
# 기존 컨테이너 종료
# ===============================
if [[ -n "$ACTIVE_CONTAINER" ]]; then
  podman stop "$ACTIVE_CONTAINER"
fi

echo "🎉 무중단 배포 완료"
