#!/bin/bash
set -e

TARGET="$1"

if [[ "$TARGET" != "blue" && "$TARGET" != "green" ]]; then
  echo "❌ 대상은 blue 또는 green 만 가능합니다."
  exit 1
fi

PODMAN=(/mnt/c/Program\ Files/RedHat/Podman/podman.exe)

UPSTREAM="routerecipt-springboot-$TARGET"

echo "🔀 Nginx 대상 → $UPSTREAM"

# nginx.conf 동적 생성
cat > nginx/nginx.conf <<EOF
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

echo "♻️ nginx 이미지 재빌드"
"${PODMAN[@]}" compose build nginx

echo "♻️ nginx 컨테이너 재생성"
"${PODMAN[@]}" rm -f routerecipt-nginx 2>/dev/null || true
"${PODMAN[@]}" compose up -d nginx

echo "✅ Nginx 전환 완료 → $UPSTREAM"
