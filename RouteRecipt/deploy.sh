#!/bin/bash
set -e

# =====================================================
# 0️⃣ 기본 설정
# =====================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

echo "📍 deploy.sh 실행 경로: $SCRIPT_DIR"
echo "📍 사용 .env 경로: $ENV_FILE"

chmod +x "$SCRIPT_DIR/switch-nginx.sh"

# =====================================================
# 1️⃣ Podman 경로 (Windows Runner 고정)
# =====================================================
PODMAN=(/mnt/c/Program\ Files/RedHat/Podman/podman.exe)

echo "🧩 사용 podman: ${PODMAN[*]}"
echo "🚀 RouteRecipt 무중단 배포 시작"

# =====================================================
# 2️⃣ 컨테이너 / 서비스 이름
# =====================================================
PROJECT="routerecipt"

BLUE_SERVICE="springboot-blue"
GREEN_SERVICE="springboot-green"
CF_SERVICE="cloudflared"

BLUE_CONTAINER="${PROJECT}-springboot-blue"
GREEN_CONTAINER="${PROJECT}-springboot-green"
CF_CONTAINER="${PROJECT}-cloudflared"

# =====================================================
# 🔒 2-1️⃣ Cloudflare Tunnel 보장 (⭐ 추가된 핵심)
# =====================================================
if ! "${PODMAN[@]}" ps --format "{{.Names}}" | grep -qx "$CF_CONTAINER"; then
  echo "☁️ cloudflared 컨테이너 없음 → 기동"
  "${PODMAN[@]}" compose up -d "$CF_SERVICE"
else
  echo "✔ cloudflared 이미 실행 중"
fi

# =====================================================
# 3️⃣ 현재 활성 컨테이너 판별
# =====================================================
if "${PODMAN[@]}" ps --format "{{.Names}}" | grep -qx "$GREEN_CONTAINER"; then
  ACTIVE_CONTAINER="$GREEN_CONTAINER"
  ACTIVE_SERVICE="$GREEN_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
  INACTIVE_SERVICE="$BLUE_SERVICE"
elif "${PODMAN[@]}" ps --format "{{.Names}}" | grep -qx "$BLUE_CONTAINER"; then
  ACTIVE_CONTAINER="$BLUE_CONTAINER"
  ACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$GREEN_CONTAINER"
  INACTIVE_SERVICE="$GREEN_SERVICE"
else
  echo "⚠️ 활성 컨테이너 없음 → blue 최초 배포"
  ACTIVE_CONTAINER=""
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
  INACTIVE_SERVICE="$BLUE_SERVICE"
fi

echo "현재 활성 컨테이너: ${ACTIVE_CONTAINER:-없음}"
echo "다음 배포 대상 컨테이너: $INACTIVE_CONTAINER"

# =====================================================
# 4️⃣ Spring Boot 이미지 빌드 (단일 서비스만)
# =====================================================
echo "🔨 이미지 빌드: $INACTIVE_SERVICE"
"${PODMAN[@]}" compose build --no-cache "$INACTIVE_SERVICE"

# =====================================================
# 5️⃣ 비활성 Spring 컨테이너만 재생성
#    (❗ DB / Redis / Nginx / Cloudflared 건드리지 않음)
# =====================================================
echo "♻️ $INACTIVE_CONTAINER 재생성"
"${PODMAN[@]}" rm -f "$INACTIVE_CONTAINER" 2>/dev/null || true
"${PODMAN[@]}" compose up -d --no-deps "$INACTIVE_SERVICE"

# =====================================================
# 6️⃣ 헬스체크
# =====================================================
echo "🩺 헬스체크 확인 중..."
HEALTH_OK=false

for i in {1..30}; do
  if "${PODMAN[@]}" exec "$INACTIVE_CONTAINER" \
     curl -sf http://localhost:8090/health | grep -q '"status":"up"'; then
    echo "✅ 헬스체크 통과"
    HEALTH_OK=true
    break
  fi
  echo "⏳ 대기 중... ($i)"
  sleep 2
done

if [[ "$HEALTH_OK" != "true" ]]; then
  echo "❌ 헬스체크 실패 → 배포 중단"
  "${PODMAN[@]}" logs "$INACTIVE_CONTAINER" --tail 50 || true
  exit 1
fi

# =====================================================
# 7️⃣ Nginx 트래픽 전환
# =====================================================
TARGET_COLOR="${INACTIVE_SERVICE#springboot-}"
echo "🔀 Nginx 트래픽 전환 → $TARGET_COLOR"
"$SCRIPT_DIR/switch-nginx.sh" "$TARGET_COLOR"

# =====================================================
# 8️⃣ 기존 Spring 컨테이너 종료
# =====================================================
if [[ -n "$ACTIVE_CONTAINER" ]]; then
  echo "🔁 기존 컨테이너 종료: $ACTIVE_CONTAINER"
  "${PODMAN[@]}" stop "$ACTIVE_CONTAINER"
fi

echo "🎉 RouteRecipt 무중단 배포 완료"
