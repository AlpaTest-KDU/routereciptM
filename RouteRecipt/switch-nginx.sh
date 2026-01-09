#!/bin/bash
set -e

# ===============================
# 사용법
# ===============================
# ./switch-nginx.sh blue | green

TARGET="$1"

# ===============================
# 1️⃣ 인자 검증
# ===============================
if [ -z "$TARGET" ]; then
  echo "❌ 사용법: $0 {blue|green}"
  exit 1
fi

if [[ "$TARGET" != "blue" && "$TARGET" != "green" ]]; then
  echo "❌ 대상은 blue 또는 green 만 가능합니다."
  exit 1
fi

# ===============================
# 2️⃣ 컨테이너 이름 정의 (compose 기준)
# ===============================
SPRING_CONTAINER="routerecipt-springboot-$TARGET"
NGINX_CONTAINER="routerecipt-nginx"
NGINX_CONF="nginx/nginx.conf"

echo "🔍 대상 Spring 컨테이너: $SPRING_CONTAINER"

# ===============================
# 3️⃣ Spring 컨테이너 RUNNING 상태 확인
# ===============================
if ! podman ps --format "{{.Names}}" | grep -q "^${SPRING_CONTAINER}$"; then
  echo "❌ Spring 컨테이너가 실행 중이 아닙니다: $SPRING_CONTAINER"
  podman ps
  exit 1
fi

# ===============================
# 4️⃣ nginx 설정 파일 경로 확인
# ===============================
if [ ! -d "nginx" ]; then
  echo "❌ nginx 디렉터리가 존재하지 않습니다."
  exit 1
fi

# ===============================
# 5️⃣ nginx.conf 재생성
# ===============================
echo "🔀 Nginx upstream 전환 → $SPRING_CONTAINER"

cat > "$NGINX_CONF" <<EOF
events {}

http {
  upstream backend {
    server ${SPRING_CONTAINER}:8090;
  }

  server {
    listen 80;

    location / {
      proxy_pass http://backend;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
    }
  }
}
EOF

echo "📄 nginx.conf 갱신 완료"

# ===============================
# 6️⃣ nginx 컨테이너 기동 / 재기동
# ===============================
if ! podman ps --format "{{.Names}}" | grep -q "^${NGINX_CONTAINER}$"; then
  echo "🚀 nginx 컨테이너가 없어 새로 기동합니다."
  podman compose up -d nginx
else
  echo "♻️ nginx 설정 reload"
  podman exec "$NGINX_CONTAINER" nginx -t
  podman exec "$NGINX_CONTAINER" nginx -s reload
fi

echo "✅ Nginx 트래픽 전환 완료 → $SPRING_CONTAINER"
