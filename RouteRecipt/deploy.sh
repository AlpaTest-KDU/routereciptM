#!/bin/bash
set -e

echo "======================================"
echo "🚀 RouteRecipt Blue/Green Deploy Start"
echo "======================================"

PROJECT="routerecipt"

BLUE_SERVICE="springboot-blue"
GREEN_SERVICE="springboot-green"

BLUE_CONTAINER="${PROJECT}-${BLUE_SERVICE}"
GREEN_CONTAINER="${PROJECT}-${GREEN_SERVICE}"

NETWORK="routerecipt-net"
HEALTH_URL="/health"
HEALTH_TIMEOUT=30

PODMAN="podman"

# --------------------------------------------------
# 1️⃣ 현재 ACTIVE 컨테이너 판별
# --------------------------------------------------
if $PODMAN ps --format "{{.Names}}" | grep -q "^${BLUE_CONTAINER}$"; then
  ACTIVE_SERVICE=$BLUE_SERVICE
  ACTIVE_CONTAINER=$BLUE_CONTAINER
  INACTIVE_SERVICE=$GREEN_SERVICE
  INACTIVE_CONTAINER=$GREEN_CONTAINER
else
  ACTIVE_SERVICE=$GREEN_SERVICE
  ACTIVE_CONTAINER=$GREEN_CONTAINER
  INACTIVE_SERVICE=$BLUE_SERVICE
  INACTIVE_CONTAINER=$BLUE_CONTAINER
fi

echo "🟢 ACTIVE  : $ACTIVE_CONTAINER"
echo "🔵 TARGET  : $INACTIVE_CONTAINER"

# --------------------------------------------------
# 2️⃣ INACTIVE 이미지 재빌드
# --------------------------------------------------
echo "🔨 Build image for $INACTIVE_SERVICE"
$PODMAN compose build --no-cache $INACTIVE_SERVICE

# --------------------------------------------------
# 3️⃣ INACTIVE 컨테이너 기동
# --------------------------------------------------
echo "🚀 Start $INACTIVE_CONTAINER"
$PODMAN compose up -d $INACTIVE_SERVICE

# --------------------------------------------------
# 4️⃣ Health Check
# --------------------------------------------------
echo "🩺 Health check started..."

START_TIME=$(date +%s)
while true; do
  STATUS=$($PODMAN inspect --format='{{.State.Health.Status}}' "$INACTIVE_CONTAINER" 2>/dev/null || echo "starting")

  if [ "$STATUS" == "healthy" ]; then
    echo "✅ Health check passed"
    break
  fi

  NOW=$(date +%s)
  ELAPSED=$((NOW - START_TIME))

  if [ $ELAPSED -ge $HEALTH_TIMEOUT ]; then
    echo "❌ Health check failed (timeout)"
    echo "⛔ Rollback: stopping $INACTIVE_CONTAINER"
    $PODMAN stop $INACTIVE_CONTAINER
    exit 1
  fi

  sleep 2
done

# --------------------------------------------------
# 5️⃣ Nginx 전환
# --------------------------------------------------
echo "🔁 Switching Nginx upstream to $INACTIVE_SERVICE"

$PODMAN exec routerecipt-nginx sh -c "
sed -i 's/${ACTIVE_SERVICE}/${INACTIVE_SERVICE}/g' /etc/nginx/conf.d/*.conf &&
nginx -s reload
"

echo "🌐 Nginx switched"

# --------------------------------------------------
# 6️⃣ 이전 ACTIVE 컨테이너 종료
# --------------------------------------------------
echo "🛑 Stop old container: $ACTIVE_CONTAINER"
$PODMAN stop $ACTIVE_CONTAINER

echo "======================================"
echo "🎉 Deploy completed successfully"
echo "======================================"
