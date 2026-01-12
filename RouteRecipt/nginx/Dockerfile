FROM nginx:alpine

# 기본 설정 제거
RUN rm -f /etc/nginx/conf.d/default.conf

# 우리가 만든 설정 복사
COPY routerecipt.conf /etc/nginx/conf.d/routerecipt.conf
