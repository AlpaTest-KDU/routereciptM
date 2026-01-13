FROM nginx:1.29-alpine

COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/

RUN ln -sf /etc/nginx/conf.d/upstream-blue.conf \
           /etc/nginx/conf.d/active-upstream.conf \
 && nginx -t
