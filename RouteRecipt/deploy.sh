#!/bin/bash
set -e

#######################################
# ⭐ 실행 위치 고정
#######################################
cd "$(dirname "$0")"

#######################################
# ⭐ Podman 실행 파일 자동 탐색
#######################################
if command -v podman >/dev/null 2>&1; then
  PODMAN="podman"
elif [ -x "/mnt/c/Program Files/RedHat/Podman/Podman.exe" ]; then
  PODMAN="/mnt/c/Program Files/RedHat/Podman/Podman.exe"
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
# 1️⃣ 현재 활성 판단 (green 기준)
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
# 2️⃣ 신규 컨테이너 기동
#######################################
echo "▶ ${INACTIVE} 기동"
"$PODMAN" start "routerecipt-${INACTIVE}"

#######################################
# 3️⃣ 기동 안정화 대기
#######################################
echo "⏳ 안정화 대기"
sleep 10

#######################################
# 4️⃣ 기존 컨테이너 종료
#######################################
echo "▶ ${ACTIVE} 종료"
"$PODMAN" stop "routerecipt-${ACTIVE}"

echo "✅ 배포 완료 (nginx untouched)"
