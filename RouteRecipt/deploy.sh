#!/bin/bash
set -e

# ===============================
# 고정 설정
# ===============================
ENV_FILE="/home/sdedu01/actions-runner/.env"
NETWORK="routerecipt-net"
IMAGE="localhost/routereciptd_springboot:latest"

BLUE="routerecipt-springboot-blue"
GREEN="routerecipt-springboot-green"

# ===============================
# ENV 파일 체크
# ===============================
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ ENV 파일 없음: $ENV_FILE"
  exit 1
fi

echo "📁 ENV_FILE = $ENV_FILE"

# ===============================
# 이미지 존재 여부 체크
# ===============================
if ! podman image exists "$IMAGE"; then
  echo "❌ 이미지 없음: $IMAGE"
  exit 1
fi

echo "🖼️  IMAGE OK: $IMAGE"

# ===============================
# 네트워크 보장
# ===============================
if ! podman network exists "$NETWORK"; then
  echo "🌐 네트워크 없음 → 생성: $NETWORK"
  podman network create "$NETWORK"
else
  echo "🌐 네트워크 존재: $NETWORK"
fi

# ===============================
# Active / Inactive 판별
# ===============================
if podman ps --format "{{.Names}}" | grep -q "^${BLUE}$"; then
  ACTIVE="$BLUE"
  INACTIVE="$GREEN"
  PORT="8091"
elif podman ps --format "{{.Names}}" | grep -q "^${GREEN}$"; then
  ACTIVE="$GREEN"
  INACTIVE="$BLUE"
  PORT="8090"
else
  echo "ℹ️ 실행 중 컨테이너 없음 → 최초 배포"
  ACTIVE="none"
  INACTIVE="$BLUE"
  PORT="8090"
fi

echo "🟢 Active  : $ACTIVE"
echo "🔵 Inactive: $INACTIVE (port=$PORT)"

# ===============================
# Inactive 컨테이너 재기동
# ===============================
podman stop "$INACTIVE" 2>/dev/null || true
podman rm   "$INACTIVE" 2>/dev/null || true

podman run -d \
  --name "$INACTIVE" \
  --network "$NETWORK" \
  -p "${PORT}:8090" \
  --env-file "$ENV_FILE" \
  "$IMAGE"

# ===============================
# Health Check
# ===============================
HEALTH_URL="http://localhost:${PORT}/actuator/health"

echo "🔎 Health check: $HEALTH_URL"

for i in {1..20}; do
  if curl -sf "$HEALTH_URL" | grep -q '"status":"UP"'; then
    echo "✅ Health OK"
    exit 0
  fi
  sleep 3
done

echo "❌ Health check failed"
exit 1
