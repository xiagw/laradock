## arch: x86_64
ARG JDK_IMAGE=${JDK_IMAGE}
ARG JDK_VERSION=${JDK_VERSION}
# ARG JDK_IMAGE=amazoncorretto:11
# ARG JDK_IMAGE=amazoncorretto:17

## arch: arm64
# ARG JDK_IMAGE=arm64v8/openjdk:8

FROM ${JDK_IMAGE}:${JDK_VERSION}

ARG IN_CHINA=${CHANGE_SOURCE}
ARG CHANGE_SOURCE=${CHANGE_SOURCE}
ARG MVN_PROFILE=main
ARG TZ=Asia/Shanghai
ARG INSTALL_FONTS=false
ARG INSTALL_FFMPEG=false
ARG BUILD_URL=https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh

ENV TZ=$TZ

WORKDIR /app
EXPOSE 8080 8081 8082
VOLUME /app
CMD ["/opt/run.sh"]

# COPY --from=builder /jars/ .
RUN set -xe; \
    if [ -f /opt/build.sh ]; then echo "found /opt/build.sh"; else curl -fLo /opt/build.sh $BUILD_URL; fi; \
    bash /opt/build.sh

USER 1000
