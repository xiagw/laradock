# FROM nginx:stable-alpine
FROM registry.cn-hangzhou.aliyuncs.com/flyh5/flyh5:nginx-stable-alpine

LABEL maintainer="Mahmoud Zalt <mahmoud@zalt.me>"

# COPY nginx.conf /etc/nginx/

# If you're in China, or you need to change sources, will be set CHANGE_SOURCE to true in .env.

ARG CHANGE_SOURCE=false
RUN if [ ${CHANGE_SOURCE} = true ]; then \
    # Change application source from dl-cdn.alpinelinux.org to aliyun source
    sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/' /etc/apk/repositories \
;fi

RUN apk update \
    && apk upgrade \
    && apk --update add --no-cache logrotate \
    && apk --update add --no-cache openssl \
    && apk --update add --no-cache bash curl

# RUN apk add --no-cache curl

RUN set -x ; \
    touch /var/log/messages; \
    addgroup -g 1000 -S www-data ; \
    adduser -u 1000 -D -S -G www-data www-data

# ARG PHP_UPSTREAM_CONTAINER=php-fpm
# ARG PHP_UPSTREAM_PORT=9000

# Create 'messages' file used from 'logrotate'
# RUN touch /var/log/messages

# Copy 'logrotate' config file
# COPY logrotate/nginx /etc/logrotate.d/

# Set upstream conf and remove the default conf
# RUN echo "upstream php-upstream { server ${PHP_UPSTREAM_CONTAINER}:${PHP_UPSTREAM_PORT}; }" > /etc/nginx/php-upstream.conf \
#     && rm /etc/nginx/conf.d/default.conf

COPY ./startup.sh /docker-entrypoint.d/startup.sh
RUN sed -i 's/\r//g' /docker-entrypoint.d/startup.sh; chmod +x /docker-entrypoint.d/startup.sh
# CMD ["/bin/bash", "/opt/startup.sh"]

EXPOSE 80 81 443
