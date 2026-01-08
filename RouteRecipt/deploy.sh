#!/bin/bash

pwd
ls -al
ls -al RouteRecipt || true

set -e

# ⭐⭐⭐ 이 줄이 핵심 ⭐⭐⭐
cd "$(dirname "$0")"

PODMAN=(/mnt/c/Program\ Files/RedHat/Podman/podman.exe)

PROJECT="routerecipt"

BLUE_SERVICE="springboot-blue"
GREEN_SERVICE="springboot-green"

BLUE_CONTAINER="${PROJECT}-${BLUE_SERVICE}"
GREEN_CONTAINER="${PROJECT}-${GREEN_SERVICE}"

echo "🚀 RouteRecipt 무중단 배포 시작"

# 1️⃣ 현재 활성 컨테이너 판별
if "${PODMAN[@]}" ps --format "{{.Names}}" | grep -q -- "$BLUE_CONTAINER"; then
  ACTIVE_SERVICE="$BLUE_SERVICE"
  ACTIVE_CONTAINER="$BLUE_CONTAINER"
  INACTIVE_SERVICE="$GREEN_SERVICE"
  INACTIVE_CONTAINER="$GREEN_CONTAINER"
else
  ACTIVE_SERVICE="$GREEN_SERVICE"
  ACTIVE_CONTAINER="$GREEN_CONTAINER"
  INACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
fi

echo "현재 활성 컨테이너: $ACTIVE_CONTAINER"
echo "다음 배포 대상 컨테이너: $INACTIVE_CONTAINER"

# 2️⃣ 이미지 재빌드
echo "🔨 이미지 빌드: $INACTIVE_SERVICE"
"${PODMAN[@]}" compose build --no-cache "$INACTIVE_SERVICE"

# 3️⃣ 비활성 서비스 재생성 (⭐ 핵심)
echo "♻️ $INACTIVE_SERVICE 재생성"
"${PODMAN[@]}" compose down "$INACTIVE_SERVICE"
"${PODMAN[@]}" compose up -d "$INACTIVE_SERVICE"

# 4️⃣ 헬스체크
echo "🩺 헬스체크 확인 중..."
for i in {1..30}; do
  if "${PODMAN[@]}" exec "$INACTIVE_CONTAINER" \
      curl -s http://localhost:8090/health | grep -q '"status":"up"'; then
    echo "✅ 헬스체크 통과"
    break
  fi
  echo "⏳ 대기 중... ($i)"
  sleep 2
done

# 5️⃣ nginx 트래픽 전환
echo "🔀 Nginx 트래픽 전환"
./switch-nginx.sh "$INACTIVE_CONTAINER"

# 6️⃣ 기존 서비스 종료
echo "🔁 기존 컨테이너 종료: $ACTIVE_CONTAINER"
"${PODMAN[@]}" compose stop "$ACTIVE_SERVICE"

echo "🎉 무중단 배포 완료"
