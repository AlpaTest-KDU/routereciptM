#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

echo "📍 deploy.sh 실행 경로: $SCRIPT_DIR"
echo "📍 사용 .env 경로: $ENV_FILE"

chmod +x "$SCRIPT_DIR/switch-nginx.sh"

echo "📦 .env는 podman compose에서 env_file로 사용합니다"

# ===============================
# 0️⃣ Nginx 설정 파일 자동 생성
# (routerecipt.conf ❌ / nginx.conf만)
# ===============================
NGINX_DIR="$SCRIPT_DIR/nginx"
CONF_DIR="$NGINX_DIR/conf.d"

mkdir -p "$CONF_DIR"

cat > "$NGINX_DIR/nginx.conf" << 'EOF'
user nginx;
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    # 업로드 용량 제한 (전역)
    client_max_body_size 20M;

    include /etc/nginx/conf.d/*.conf;
}
EOF

echo "✅ nginx.conf 생성 완료 (client_max_body_size = 20M)"

# ===============================
# Podman 설정
# ===============================
PODMAN=(/mnt/c/Program\ Files/RedHat/Podman/podman.exe)

PROJECT="routerecipt"

BLUE_SERVICE="springboot-blue"
GREEN_SERVICE="springboot-green"
AI_SERVICE="fastapi-ai"

BLUE_CONTAINER="${PROJECT}-${BLUE_SERVICE}"
GREEN_CONTAINER="${PROJECT}-${GREEN_SERVICE}"
AI_CONTAINER="${PROJECT}-fastapi-ai"

echo "🚀 RouteRecipt 무중단 배포 시작"

echo "📦 환경변수는 podman compose env_file(.env)로 주입됩니다"

# ===============================
# 2️⃣ AI 서비스 보장
# ===============================
echo "🤖 AI 서비스 확인 중..."

if ! "${PODMAN[@]}" ps --format "{{.Names}}" | grep -q "^${AI_CONTAINER}$"; then
  echo "▶ fastapi-ai 컨테이너 없음 → 기동"
  "${PODMAN[@]}" compose up -d "$AI_SERVICE"
else
  echo "✔ fastapi-ai 컨테이너 이미 실행 중"
fi

# ===============================
# 3️⃣ 현재 활성 Blue / Green 판별
# ===============================
BLUE_RUNNING=$("${PODMAN[@]}" ps --format "{{.Names}}" | grep -q "^${BLUE_CONTAINER}$" && echo yes || echo no)
GREEN_RUNNING=$("${PODMAN[@]}" ps --format "{{.Names}}" | grep -q "^${GREEN_CONTAINER}$" && echo yes || echo no)

if [[ "$BLUE_RUNNING" == "yes" ]]; then
  ACTIVE_SERVICE="$BLUE_SERVICE"
  ACTIVE_CONTAINER="$BLUE_CONTAINER"
  INACTIVE_SERVICE="$GREEN_SERVICE"
  INACTIVE_CONTAINER="$GREEN_CONTAINER"
elif [[ "$GREEN_RUNNING" == "yes" ]]; then
  ACTIVE_SERVICE="$GREEN_SERVICE"
  ACTIVE_CONTAINER="$GREEN_CONTAINER"
  INACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
else
  echo "⚠️ blue/green 모두 실행 중이 아님 (최초 배포)"
  ACTIVE_CONTAINER=""
  INACTIVE_SERVICE="$BLUE_SERVICE"
  INACTIVE_CONTAINER="$BLUE_CONTAINER"
fi

echo "현재 활성 컨테이너: ${ACTIVE_CONTAINER:-없음}"
echo "다음 배포 대상 컨테이너: $INACTIVE_CONTAINER"

# ===============================
# 4️⃣ Spring Boot 이미지 빌드
# ===============================
echo "🔨 이미지 빌드: $INACTIVE_SERVICE"
"${PODMAN[@]}" compose build --no-cache "$INACTIVE_SERVICE"

# ===============================
# 5️⃣ 비활성 컨테이너 재생성
# ===============================
echo "♻️ $INACTIVE_CONTAINER 재생성"
"${PODMAN[@]}" rm -f "$INACTIVE_CONTAINER" 2>/dev/null || true
"${PODMAN[@]}" compose up -d "$INACTIVE_SERVICE"

# ===============================
# 6️⃣ 헬스체크
# ===============================
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

# ===============================
# 7️⃣ Nginx 트래픽 전환
# ===============================
TARGET_COLOR=$(echo "$INACTIVE_SERVICE" | sed 's/springboot-//')
echo "🔀 Nginx 트래픽 전환 → $TARGET_COLOR"
"$SCRIPT_DIR/switch-nginx.sh" "$TARGET_COLOR"

# ===============================
# 8️⃣ 기존 컨테이너 종료
# ===============================
if [[ -n "$ACTIVE_CONTAINER" ]]; then
  echo "🔁 기존 컨테이너 종료: $ACTIVE_CONTAINER"
  "${PODMAN[@]}" stop "$ACTIVE_CONTAINER"
else
  echo "ℹ️ 기존 활성 컨테이너 없음 (최초 배포)"
fi

echo "🎉 무중단 배포 완료"
