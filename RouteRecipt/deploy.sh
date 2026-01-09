#!/bin/bash
set -e

# ===============================
# 0️⃣ 실행 위치 고정 (CI 필수)
# ===============================
cd "$(dirname "$0")"

echo "📂 현재 위치:"
pwd
ls -al

chmod +x switch-nginx.sh

PODMAN=(/mnt/c/Program\ Files/RedHat/Podman/podman.exe)

PROJECT="routerecipt"

BLUE_SERVICE="springboot-blue"
GREEN_SERVICE="springboot-green"
AI_SERVICE="fastapi-ai"

BLUE_CONTAINER="${PROJECT}-${BLUE_SERVICE}"
GREEN_CONTAINER="${PROJECT}-${GREEN_SERVICE}"
AI_CONTAINER="${PROJECT}-fastapi-ai"

echo "🚀 RouteRecipt 무중단 배포 시작"

# ===============================
# 1️⃣ 필수 환경변수 검증 (CI에서 내려온 값 기준)
# ===============================
REQUIRED_VARS=(
  DB_USER
  DB_PASSWORD
  MARIADB_ROOT_PASSWORD
  OPENAI_API_KEY
  AI_CATEGORY_URL
  CLOVA_URL
  CLOVA_SECRET
)

for VAR in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!VAR}" ]]; then
    echo "❌ 필수 환경변수 누락: $VAR"
    exit 1
  fi
done

echo "✅ 환경변수 검증 완료"

# ===============================
# 2️⃣ AI 서비스 보장 (fastapi-ai)
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
./switch-nginx.sh "$TARGET_COLOR"

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
