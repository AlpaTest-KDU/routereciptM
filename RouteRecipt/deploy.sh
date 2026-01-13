#!/bin/bash
set -e

cd "$(dirname "$0")"

BLUE="routerecipt-springboot-blue"
GREEN="routerecipt-springboot-green"
IMAGE="localhost/routereciptd_springboot:latest"

if podman ps --format "{{.Names}}" | grep -q "$BLUE"; then
  ACTIVE="$BLUE"
  INACTIVE="$GREEN"
  PORT="8091"
else
  ACTIVE="$GREEN"
  INACTIVE="$BLUE"
  PORT="8090"
fi

echo "Active  : $ACTIVE"
echo "Inactive: $INACTIVE (port=$PORT)"

podman stop $INACTIVE || true
podman rm $INACTIVE || true

podman run -d --name $INACTIVE \
  --network routerecipt-net \
  -p ${PORT}:8090 \
  --env-file .env \
  $IMAGE

HEALTH_URL="http://localhost:${PORT}/health"

for i in {1..20}; do
  if curl -sf "$HEALTH_URL" > /dev/null; then
    echo "✅ Health OK"
    exit 0
  fi
  sleep 3
done

echo "❌ Health check failed"
exit 1
