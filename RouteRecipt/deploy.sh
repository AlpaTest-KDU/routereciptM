#!/bin/bash
set -e

############################################
# 기본 경로 설정
############################################
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="/home/sdedu01/routerecipt/.env"   # 🔴 실제 .env 절대경로로 수정
IMAGE="localhost/routereciptd_springboot:latest"

BLUE="routerecipt-springboot-blue"
GREEN="routerecipt-springboot-green"

echo "📁 BASE_DIR = $BASE_DIR"
cd "$BASE_DIR"

############################################
# 1️⃣ 이미지 존재 여부 확인 및 빌드
############################################
echo "🔍 이미지 존재 여부 확인"
if ! podman image exists "$IMAGE"; then
  echo "📦 이미지 없음 → 빌드 수행"
  podman build -t "$IMAGE" .
fi

############################################
# 2️⃣ Active / Inactive 판단
############################################
if podman ps --format "{{.Names}}" | grep -q "^${BLUE}$"; then
  ACTIVE="$BLUE"
  INACTIVE="$GREEN"
  PORT="8091"
else
  ACTIVE="$GREEN"
  INACTIVE="$BLUE"
  PORT="8090"
fi

echo "🟢 Active  : $ACTIVE"
echo "🔵 Inactive: $INACTIVE (port=$PORT)"

############################################
# 3️⃣ Inactive 컨테이너 교체
############################################
podman stop "$INACTIVE" || true
podman rm "$INACTIVE" || true

podman run -d \
  --name "$INACTIVE" \
  --network routerecipt-net \
  -p "${PORT}:8090" \
  --env-file "$ENV_FILE" \
  "$IMAGE"

############################################
# 4️⃣ Health Check (Inactive만)
############################################
HEALTH_URL="http://localhost:${PORT}/health"
echo "⏳ Health check: $HEALTH_URL"

for i in {1..20}; do
  if curl -sf "$HEALTH_URL" > /dev/null; then
    echo "✅ Health OK"
    exit 0
  fi
  sleep 3
done

echo "❌ Health check failed"
exit 1
