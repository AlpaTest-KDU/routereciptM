#!/bin/bash
set -e

cd "$(dirname "$0")"

if command -v podman >/dev/null 2>&1; then
  PODMAN=(podman)
else
  PODMAN=("/mnt/c/Program Files/RedHat/Podman/podman.exe")
fi

IMAGE="localhost/routereciptd_springboot"
NETWORK="routerecipt_routerecipt-net"
ALIAS="routerecipt-backend"

BLUE="springboot-blue"
GREEN="springboot-green"

if "${PODMAN[@]}" ps --format "{{.Names}}" | grep -q "^routerecipt-${BLUE}$"; then
  ACTIVE="$BLUE"
  INACTIVE="$GREEN"
  TAG="green"
else
  ACTIVE="$GREEN"
  INACTIVE="$BLUE"
  TAG="blue"
fi

echo "ACTIVE=$ACTIVE"
echo "INACTIVE=$INACTIVE"

"${PODMAN[@]}" rm -f "routerecipt-${INACTIVE}" 2>/dev/null || true

"${PODMAN[@]}" run -d \
  --name "routerecipt-${INACTIVE}" \
  --network "$NETWORK" \
  --network-alias "$ALIAS" \
  --env-file .env \
  "${IMAGE}:${TAG}"

sleep 8

"${PODMAN[@]}" stop "routerecipt-${ACTIVE}" 2>/dev/null || true

"${PODMAN[@]}" exec routerecipt-nginx nginx -s reload || true

echo "✅ Blue-Green switch complete"
