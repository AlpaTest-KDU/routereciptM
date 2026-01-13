#!/bin/bash
set -e

COLOR="$1"

if [[ "$COLOR" != "blue" && "$COLOR" != "green" ]]; then
  echo "❌ 사용법: switch-nginx.sh [blue|green]"
  exit 1
fi

NGINX_CONTAINER="routerecipt-nginx"
TARGET_CONTAINER="routerecipt-springboot-${COLOR}"

echo "🔀 Nginx upstream 전환 대상: $COLOR ($TARGET_CONTAINER)"

podman exec -it "$NGINX_CONTAINER" sh -c "cat > /etc/nginx/conf.d/routerecipt.conf << 'EOF'
upstream backend {
    server ${TARGET_CONTAINER}:8090;
}

server {
    listen 80;
    server_name routerecipt.co.kr www.routerecipt.co.kr;

    client_max_body_size 200M;

    location / {
        proxy_pass http://backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF"

echo "🔍 nginx 설정 검사"
podman exec -it "$NGINX_CONTAINER" nginx -t

echo "♻️ nginx reload"
podman exec -it "$NGINX_CONTAINER" nginx -s reload

echo "✅ Nginx 트래픽 전환 완료 → $COLOR"
