#!/bin/bash
set -e

#######################################
# 실행 위치 고정
#######################################
cd "$(dirname "$0")"

#######################################
# Podman 실행 파일 탐색 (공백 안전)
#######################################
if command -v podman >/dev/null 2>&1; then
  PODMAN=(podman)
elif [ -x "/mnt/c/Program Files/RedHat/Podman/podman.exe" ]; then
  PODMAN=("/mnt/c/Program Files/RedHat/Podman/podman.exe")
else
  echo "❌ podman not found"
  exit 127
fi

#######################################
# 기본 설정
#######################################
PROJECT="routerecipt"

BLUE_TAG="blue"
GREEN_TAG="green"

BLUE_CONTAINER="springboot-blue"
GREEN_CONTAINER="springboot-green"

IMAGE="localhost/routereciptd_springboot"
NETWORK="routerecipt_routerecipt-net"
BACKEND_ALIAS="routerecipt-backend"

echo "🚀 RouteRecipt Blue-Green Deploy"
echo "▶ Using podman: ${PODMAN[*]}"

#######################################
# 활성 컨테이너 판별
#######################################
if "${PODMAN[@]}" ps --format "{{.Names}}" | grep -q "routerecipt-${BLUE_CONTAINER}"; then
  ACTIVE_CONTAINER="$BLUE_CONTAINER"
  ACTIVE_TAG="$BLUE_TAG"
  INACTIVE_CONTAINER="$GREEN_CONTAINER"
  INACTIVE_TAG="$GREEN_TAG"
else
  ACTIVE_CONTAINER="$GREEN_CONTAINER"
  ACTIVE_TAG="$GREEN_TAG"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
  INACTIVE_TAG="$BLUE_TAG"
fi

echo "현재 활성: $ACTIVE_CONTAINER ($ACTIVE_TAG)"
echo "배포 대상: $INACTIVE_CONTAINER ($INACTIVE_TAG)"

#######################################
# 기존 INACTIVE 컨테이너 정리
#######################################
"${PODMAN[@]}" stop "routerecipt-${INACTIVE_CONTAINER}" 2>/dev/null || true
"${PODMAN[@]}" rm   "routerecipt-${INACTIVE_CONTAINER}" 2>/dev/null || true

#######################################
# 신규 컨테이너 기동 (🔥 핵심)
#######################################
echo "🚀 신규 컨테이너 기동: $INACTIVE_CONTAINER"

"${PODMAN[@]}" run -d \
  --name "routerecipt-${INACTIVE_CONTAINER}" \
  --network "$NETWORK" \
  --network-alias "$BACKEND_ALIAS" \
  --env-file .env \
  "${IMAGE}:${INACTIVE_TAG}"

#######################################
# 안정화 대기
#######################################
sleep 8

#######################################
# nginx reload
#######################################
echo "🔄 nginx reload"
"${PODMAN[@]}" exec routerecipt-nginx nginx -s reload || true

#######################################
# 기존 ACTIVE 컨테이너 종료
#######################################
echo "🛑 기존 컨테이너 종료: $ACTIVE_CONTAINER"
"${PODMAN[@]}" stop "routerecipt-${ACTIVE_CONTAINER}" || true

echo "✅ 배포 완료"
