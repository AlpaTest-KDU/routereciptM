#!/bin/bash
set -e

TARGET="$1"

if [[ "$TARGET" != "blue" && "$TARGET" != "green" ]]; then
  echo "❌ 대상은 blue 또는 green 만 가능합니다."
  exit 1
fi

# ⭐ podman 절대경로 (deploy.sh와 동일)
PODMAN=(/mnt/c/Program\ Files/RedHat/Podman/podman.exe)

UPSTREAM="routerecipt-springboot-$TARGET"
NGINX_CONF="nginx/nginx.conf"

echo "🔀 Nginx upstream 전환 → $UPSTREAM"

cat > "$NGINX_CONF" <<EOF
events {}

http {
  upstream backend {
    server ${UPSTREAM}:8090;
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

echo "📄 nginx.conf 갱신 완료"

echo "♻️ nginx 컨테이너 재기동"
"${PODMAN[@]}" compose up -d nginx

echo "✅ Nginx 트래픽 전환 완료 → $UPSTREAM"
