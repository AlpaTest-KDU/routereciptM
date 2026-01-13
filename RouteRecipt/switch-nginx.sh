#!/bin/bash
set -e

COLOR="$1"

if [[ -z "$COLOR" ]]; then
  echo "❌ 색상 인자가 필요합니다 (blue | green)"
  exit 1
fi

# ===============================
# Podman 경로 고정 (deploy.sh와 동일)
# ===============================
PODMAN=(/mnt/c/Program\ Files/RedHat/Podman/podman.exe)

PROJECT="routerecipt"
NGINX_CONTAINER="${PROJECT}-nginx"
TARGET_CONTAINER="${PROJECT}-springboot-${COLOR}"

UPSTREAM_CONF="/etc/nginx/conf.d/upstream.conf"

echo "🔀 Nginx upstream 전환 대상: $COLOR ($TARGET_CONTAINER)"

# ===============================
# upstream.conf 생성
# ===============================
"${PODMAN[@]}" exec "$NGINX_CONTAINER" sh -c "cat > $UPSTREAM_CONF << 'EOF'
upstream backend {
    server ${TARGET_CONTAINER}:8090;
}
EOF"

echo "📄 upstream.conf 생성 완료"

# ===============================
# nginx 설정 검사 + reload
# ===============================
"${PODMAN[@]}" exec "$NGINX_CONTAINER" nginx -t
"${PODMAN[@]}" exec "$NGINX_CONTAINER" nginx -s reload

echo "✅ Nginx 트래픽 전환 완료 → $COLOR"
