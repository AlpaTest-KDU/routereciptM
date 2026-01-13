#!/bin/bash
set -e

#######################################
# ⭐ Podman 실행 파일 자동 탐색
#######################################
if command -v podman >/dev/null 2>&1; then
  PODMAN="podman"
elif [ -x "/mnt/c/Program Files/RedHat/Podman/podman.exe" ]; then
  PODMAN="/mnt/c/Program Files/RedHat/Podman/podman.exe"
else
  echo "❌ podman not found. Please install Podman or add it to PATH."
  exit 127
fi

#######################################
# 기본 설정
#######################################
PROJECT="routerecipt"
NGINX_CONTAINER="routerecipt-nginx"
UPSTREAM_FILE="./nginx/conf.d/upstream.conf"

BLUE="springboot-blue"
GREEN="springboot-green"

echo "🚀 RouteRecipt 배포 시작"
echo "▶ Using podman: ${PODMAN}"

#######################################
# 1️⃣ 현재 활성 컨테이너 판별
#######################################
if "$PODMAN" ps --format "{{.Names}}" | grep -q "routerecipt-${BLUE}"; then
  ACTIVE="${BLUE}"
  INACTIVE="${GREEN}"
else
  ACTIVE="${GREEN}"
  INACTIVE="${BLUE}"
fi

echo "현재 활성: $ACTIVE"
echo "배포 대상: $INACTIVE"

#######################################
# 2️⃣ 신규 컨테이너 기동
#######################################
echo "▶ ${INACTIVE} 기동"
"$PODMAN" start "routerecipt-${INACTIVE}"

sleep 5

#######################################
# 3️⃣ upstream.conf 교체
#######################################
echo "▶ upstream 전환 → ${INACTIVE}"
cat > "${UPSTREAM_FILE}" <<EOF
upstream routerecipt_backend {
    server routerecipt-${INACTIVE}:8090;
}
EOF

#######################################
# 4️⃣ nginx reload
#######################################
echo "▶ nginx reload"
"$PODMAN" exec "${NGINX_CONTAINER}" nginx -s reload

#######################################
# 5️⃣ 기존 컨테이너 종료
#######################################
echo "▶ ${ACTIVE} 종료"
"$PODMAN" stop "routerecipt-${ACTIVE}"

echo "✅ 배포 완료"
