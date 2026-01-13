#!/bin/bash
set -e

echo "🚀 RouteRecipt CI/CD 무중단 배포 시작"

# ===============================
# 0️⃣ 기본 경로
# ===============================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ===============================
# 1️⃣ Podman 설치 보장 (CI Linux)
# ===============================
if ! command -v podman >/dev/null 2>&1; then
  echo "🔧 Podman 미설치 → 설치 진행"
  sudo apt-get update
  sudo apt-get install -y podman
fi

echo "🧩 Podman 확인:"
podman --version

# podman-compose 보장
if ! podman compose version >/dev/null 2>&1; then
  echo "🔧 podman-compose 설치"
  pip3 install --user podman-compose
  export PATH="$HOME/.local/bin:$PATH"
fi

# ===============================
# 2️⃣ 서비스 / 컨테이너 이름
# ===============================
PROJECT="routerecipt"

BLUE_SERVICE="springboot-blue"
GREEN_SERVICE="springboot-green"
AI_SERVICE="fastapi-ai"
CF_SERVICE="cloudflared"

BLUE_CONTAINER="${PROJECT}-springboot-blue"
GREEN_CONTAINER="${PROJECT}-springboot-green"
AI_CONTAINER="${PROJECT}-fastapi-ai"
CF_CONTAINER="${PROJECT}-cloudflared"

# ===============================
# 3️⃣ 필수 인프라 보장 (DB / Redis / AI / Nginx / Cloudflare)
# ===============================
echo "📦 인프라 서비스 보장 기동"
podman compose up -d mariadb redis nginx fastapi-ai cloudflared

# ===============================
# 4️⃣ 현재 활성 Blue / Green 판별
# ===============================
if podman ps --format "{{.Names}}" | grep -qx "$BLUE_CONTAINER"; then
  ACTIVE_CONTAINER="$BLUE_CONTAINER"
  ACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_SERVICE="$GREEN_SERVICE"
  INACTIVE_CONTAINER="$GREEN_CONTAINER"
elif podman ps --format "{{.Names}}" | grep -qx "$GREEN_CONTAINER"; then
  ACTIVE_CONTAINER="$GREEN_CONTAINER"
  ACTIVE_SERVICE="$GREEN_SERVICE"
  INACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
else
  echo "⚠️ 최초 배포 → blue 선택"
  ACTIVE_CONTAINER=""
  INACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
fi

echo "현재 활성 컨테이너: ${ACTIVE_CONTAINER:-없음}"
echo "다음 배포 대상: $INACTIVE_CONTAINER"

# ===============================
# 5️⃣ Spring Boot 이미지 빌드
# ===============================
echo "🔨 Spring 이미지 빌드: $INACTIVE_SERVICE"
podman compose build --no-cache "$INACTIVE_SERVICE"

# ===============================
# 6️⃣ 비활성 Spring 컨테이너만 재기동
# ===============================
echo "♻️ $INACTIVE_CONTAINER 재기동"
podman rm -f "$INACTIVE_CONTAINER" 2>/dev/null || true
podman compose up -d --no-deps "$INACTIVE_SERVICE"

# ===============================
# 7️⃣ 헬스체크
# ===============================
echo "🩺 헬스체크 대기"
for i in {1..30}; do
  if podman exec "$INACTIVE_CONTAINER" \
    curl -sf http://localhost:8090/health | grep -q '"status":"up"'; then
    echo "✅ 헬스체크 통과"
    break
  fi
  echo "⏳ 대기 중 ($i)"
  sleep 2
done

# ===============================
# 8️⃣ Nginx 트래픽 전환
# ===============================
TARGET_COLOR="${INACTIVE_SERVICE#springboot-}"
echo "🔀 Nginx 트래픽 전환 → $TARGET_COLOR"
chmod +x switch-nginx.sh
./switch-nginx.sh "$TARGET_COLOR"

# ===============================
# 9️⃣ 기존 컨테이너 종료
# ===============================
if [[ -n "$ACTIVE_CONTAINER" ]]; then
  echo "🔁 기존 컨테이너 종료: $ACTIVE_CONTAINER"
  podman stop "$ACTIVE_CONTAINER"
fi

echo "🎉 RouteRecipt 무중단 배포 완료"
