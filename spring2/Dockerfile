ARG MIRROR=
ARG JDK_VERSION=8
FROM ${MIRROR}amazoncorretto:${JDK_VERSION}

ARG IN_CHINA=${CHANGE_SOURCE}
ARG CHANGE_SOURCE=${CHANGE_SOURCE}
ARG MVN_PROFILE=main
ARG TZ=Asia/Shanghai
ARG INSTALL_FONTS=false
ARG INSTALL_FFMPEG=false
ARG INSTALL_LIBREOFFICE=false
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh

ENV TZ=$TZ

WORKDIR /app
EXPOSE 8080 8081 8082
VOLUME /app
CMD ["bash", "/opt/run.sh"]

# COPY --from=builder /jars/ .
RUN set -xe; \
    if [ ! -f /opt/build.sh ]; then curl -fLo /opt/build.sh $BUILD_URL; fi; \
    if [ -f /opt/build.sh ]; then bash /opt/build.sh; fi

USER 1000
