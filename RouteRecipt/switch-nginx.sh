#!/bin/bash
set -e

TARGET_COLOR="$1"

if [[ -z "$TARGET_COLOR" ]]; then
  echo "❌ 사용법: switch-nginx.sh [blue|green]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NGINX_DIR="$SCRIPT_DIR/nginx"
CONF_DIR="$NGINX_DIR/conf.d"
UPSTREAM_CONF="$CONF_DIR/upstream.conf"

BLUE_CONTAINER="routerecipt-springboot-blue"
GREEN_CONTAINER="routerecipt-springboot-green"

case "$TARGET_COLOR" in
  blue)
    TARGET_CONTAINER="$BLUE_CONTAINER"
    ;;
  green)
    TARGET_CONTAINER="$GREEN_CONTAINER"
    ;;
  *)
    echo "❌ 잘못된 인자: $TARGET_COLOR (blue 또는 green)"
    exit 1
    ;;
esac

echo "🔀 Nginx upstream 전환 대상: $TARGET_COLOR ($TARGET_CONTAINER)"

mkdir -p "$CONF_DIR"

cat > "$UPSTREAM_CONF" << EOF
upstream backend {
    server $TARGET_CONTAINER:8090;
}
EOF

echo "📄 upstream.conf 생성 완료"
cat "$UPSTREAM_CONF"

echo "🔍 nginx 설정 검사"
nginx -t

echo "♻️ nginx reload"
nginx -s reload

echo "✅ Nginx 트래픽 전환 완료 → $TARGET_COLOR"
