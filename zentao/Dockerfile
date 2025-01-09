FROM debian:12-slim

LABEL maintainer="xiagw <fxiaxiaoyu@gmail.com>"

ARG CHANGE_SOURCE=false
ARG ZT_VERSION=${ZT_VERSION:-21.3}
ENV ZT_VERSION=${ZT_VERSION:-21.3}
EXPOSE 80
VOLUME /app/zentaopms
ENTRYPOINT ["/app/docker-entrypoint.sh"]
WORKDIR /var/www
COPY root/ /
RUN bash /app/build.sh
