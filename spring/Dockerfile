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
RUN set -xe; \
    if [ -f /opt/build.sh ]; then \
    echo "found /opt/build.sh"; \
    else \
    curl -fLo /opt/build.sh https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/root/opt/build.sh; \
    fi; \
    bash /opt/build.sh

USER 1000