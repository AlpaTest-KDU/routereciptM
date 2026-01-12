FROM nginx:alpine

# 기본 설정 제거
RUN rm -f /etc/nginx/conf.d/default.conf

# 메인 도메인 설정
COPY routerecipt.conf /etc/nginx/conf.d/routerecipt.conf

# upload 도메인 리다이렉트 설정
COPY upload.conf /etc/nginx/conf.d/upload.conf
