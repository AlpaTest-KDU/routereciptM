#!/bin/bash
set -e

#######################################
# ⭐ 실행 위치 고정 (M 레포 기준)
#######################################
cd "$(dirname "$0")"

#######################################
# ⭐ Podman 실행 파일 자동 탐색
#######################################
if command -v podman >/dev/null 2>&1; then
  PODMAN="podman"
elif [ -x "/mnt/c/Program Files/RedHat/Podman/podman.exe" ]; then
  PODMAN="/mnt/c/Program Files/RedHat/Podman/podman.exe"
else
  echo "❌ podman not found"
  exit 127
fi

#######################################
# 기본 설정
#######################################
PROJECT="routerecipt"
GREEN="springboot-green"
BLUE="springboot-blue"

echo "🚀 RouteRecipt 배포 시작"
echo "▶ Using podman: ${PODMAN}"

#######################################
# 1️⃣ 현재 활성 컨테이너 판별
#######################################
if "$PODMAN" ps --format "{{.Names}}" | grep -q "^routerecipt-${GREEN}$"; then
  ACTIVE="${GREEN}"
  INACTIVE="${BLUE}"
else
  ACTIVE="${BLUE}"
  INACTIVE="${GREEN}"
fi

echo "현재 활성: ${ACTIVE}"
echo "배포 대상: ${INACTIVE}"

#######################################
# 2️⃣ 이미지 재빌드 (🔥 핵심)
#######################################
echo "🔨 이미지 재빌드: ${INACTIVE}"
"$PODMAN" compose build "${INACTIVE}"

#######################################
# 3️⃣ 신규 컨테이너 재생성
#######################################
echo "🚀 컨테이너 재기동: ${INACTIVE}"
"$PODMAN" compose up -d --force-recreate "${INACTIVE}"

#######################################
# 4️⃣ 기존 컨테이너 종료
#######################################
echo "🛑 기존 컨테이너 종료: ${ACTIVE}"
"$PODMAN" stop "routerecipt-${ACTIVE}"

#######################################
# 5️⃣ nginx reload (선택)
#######################################
"$PODMAN" exec routerecipt-nginx nginx -s reload || true

echo "✅ 배포 완료"
