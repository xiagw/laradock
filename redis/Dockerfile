FROM redis:latest

LABEL maintainer="Mahmoud Zalt <mahmoud@zalt.me>"

ARG REDIS_PASSWORD

## For security settings uncomment, make the dir, copy conf, and also start with the conf, to use it
# RUN mkdir -p /usr/local/etc/redis
COPY redis.conf /etc/redis.conf
RUN set -xe; \
  [ -n "${REDIS_PASSWORD}" ] && sed -i -e "s/.*requirepass foobared/requirepass ${REDIS_PASSWORD}/" /etc/redis.conf; \
  mkdir /run/redis; \
  chown redis:redis /run/redis

VOLUME /data

EXPOSE 6379

CMD ["redis-server", "/etc/redis.conf"]
# CMD ["redis-server"]
