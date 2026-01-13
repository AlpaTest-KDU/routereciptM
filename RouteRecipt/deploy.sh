#!/bin/bash
set -e

#######################################
# 실행 위치 고정
#######################################
cd "$(dirname "$0")"

#######################################
# Podman 실행 파일 탐색 (공백 대응)
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
BLUE="springboot-blue"
GREEN="springboot-green"
BACKEND_ALIAS="routerecipt-backend"
NETWORK="routerecipt_routerecipt-net"

echo "🚀 RouteRecipt Blue-Green Deploy"
echo "▶ Using podman: ${PODMAN[*]}"

#######################################
# 활성 컨테이너 판별
#######################################
if "${PODMAN[@]}" ps --format "{{.Names}}" | grep -q "routerecipt-${BLUE}"; then
  ACTIVE="$BLUE"
  INACTIVE="$GREEN"
else
  ACTIVE="$GREEN"
  INACTIVE="$BLUE"
fi

echo "현재 활성: $ACTIVE"
echo "배포 대상: $INACTIVE"

#######################################
# 신규 컨테이너 기동 (network alias)
#######################################
echo "🚀 신규 컨테이너 기동: $INACTIVE"

"${PODMAN[@]}" rm -f "routerecipt-${INACTIVE}" 2>/dev/null || true

"${PODMAN[@]}" run -d \
  --name "routerecipt-${INACTIVE}" \
  --network "$NETWORK" \
  --network-alias "$BACKEND_ALIAS" \
  --env-file .env \
  localhost/routereciptd_springboot:${INACTIVE}

#######################################
# 안정화 대기
#######################################
sleep 8

#######################################
# 기존 컨테이너 종료
#######################################
echo "🛑 기존 컨테이너 종료: $ACTIVE"
"${PODMAN[@]}" stop "routerecipt-${ACTIVE}" || true

#######################################
# nginx reload
#######################################
echo "🔄 nginx reload"
"${PODMAN[@]}" exec routerecipt-nginx nginx -s reload || true

echo "✅ 배포 완료"
