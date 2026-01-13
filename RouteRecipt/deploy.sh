#!/bin/bash
set -e

cd "$(dirname "$0")"

PODMAN=podman

PROJECT="routerecipt"
GREEN="springboot-green"
BLUE="springboot-blue"

echo "🚀 RouteRecipt 배포 시작"

# 1️⃣ 활성 컨테이너 판별
if "$PODMAN" ps --format "{{.Names}}" | grep -q "^routerecipt-${GREEN}$"; then
  ACTIVE="${GREEN}"
  INACTIVE="${BLUE}"
else
  ACTIVE="${BLUE}"
  INACTIVE="${GREEN}"
fi

echo "현재 활성: ${ACTIVE}"
echo "배포 대상: ${INACTIVE}"

# 🔥 핵심 1: 이미지 재빌드
echo "🔨 이미지 재빌드: ${INACTIVE}"
"$PODMAN" compose build "${INACTIVE}"

# 🔥 핵심 2: 컨테이너 재생성
echo "🚀 컨테이너 재기동: ${INACTIVE}"
"$PODMAN" compose up -d --force-recreate "${INACTIVE}"

# 🔥 핵심 3: 기존 컨테이너 종료
echo "🛑 기존 컨테이너 종료: ${ACTIVE}"
"$PODMAN" stop "routerecipt-${ACTIVE}"

# 🔥 (선택) nginx reload
"$PODMAN" exec routerecipt-nginx nginx -s reload || true

echo "✅ 배포 완료"
