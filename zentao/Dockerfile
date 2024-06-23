FROM debian:12-slim

LABEL maintainer="xiagw <fxiaxiaoyu@gmail.com>"

ARG CHANGE_SOURCE=false
ARG ZENTAO_VERSION=20.1.1
EXPOSE 80
VOLUME /app/zentaopms
ENTRYPOINT ["/app/docker-entrypoint.sh"]
WORKDIR /var/www
COPY root/ /
RUN bash /app/build.sh

