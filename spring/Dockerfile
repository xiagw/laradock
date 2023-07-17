ARG JDK_VERSION=${JDK_VERSION}
FROM openjdk:${JDK_VERSION}

ARG IN_CHINA=${CHANGE_SOURCE}
ARG CHANGE_SOURCE=${CHANGE_SOURCE}
## set startup profile
ARG MVN_PROFILE=main
ARG TZ=Asia/Shanghai
ARG INSTALL_FONTS=false
ARG INSTALL_FFMPEG=false
ARG USE_JEMALLOC=${USE_JEMALLOC}

ENV TZ=$TZ
ENV USE_JEMALLOC=$USE_JEMALLOC

WORKDIR /app
EXPOSE 8080 8081 8082
# volume /data
CMD ["/opt/run.sh"]

# COPY --from=builder /jars/ .
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -fL https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/build.sh | bash

USER 1000