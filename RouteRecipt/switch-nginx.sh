#!/bin/bash
set -e

PODMAN=(/mnt/c/Program\ Files/RedHat/Podman/podman.exe)

TARGET_CONTAINER="$1"
NGINX_CONTAINER="routerecipt-nginx"
NGINX_CONF="nginx/nginx.generated.conf"

if [ -z "$TARGET_CONTAINER" ]; then
  echo "❌ 대상 컨테이너를 지정해야 합니다."
  exit 1
fi

echo "🔀 Nginx upstream 전환 → $TARGET_CONTAINER"

cat > "$NGINX_CONF" <<EOF
events {}

http {
  upstream backend {
    server ${TARGET_CONTAINER}:8090;
  }

  server {
    listen 80;

    location / {
      proxy_pass http://backend;
      proxy_set_header Host \$host;
      proxy_set_header X-Real-IP \$remote_addr;
    }
  }
}
EOF

echo "📄 nginx 설정 파일 갱신 완료"

"${PODMAN[@]}" exec "$NGINX_CONTAINER" nginx -t
"${PODMAN[@]}" exec "$NGINX_CONTAINER" nginx -s reload

echo "✅ Nginx 트래픽 전환 완료"
