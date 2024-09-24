## arch: x86_64
# ARG JDK_IMAGE_NAME=openjdk:8
# ARG JDK_IMAGE_NAME=amazoncorretto:8
# ARG JDK_IMAGE_NAME=amazoncorretto:11
# ARG JDK_IMAGE_NAME=amazoncorretto:17

FROM amazoncorretto:8

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
CMD ["bash", "/opt/run.sh"]

# COPY --from=builder /jars/ .
RUN set -xe; \
    if [ ! -f /opt/build.sh ]; then curl -fLo /opt/build.sh $BUILD_URL; fi; \
    if [ -f /opt/build.sh ]; then bash /opt/build.sh; fi

USER 1000
