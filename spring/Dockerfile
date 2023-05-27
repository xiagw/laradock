#############################
# FROM openjdk:11-jdk
# FROM bitnami/tomcat:8.5 as p0
# FROM bitnami/java:1.8-prod as p0
FROM openjdk:8u332

ARG IN_CHINA=false
ARG CHANGE_SOURCE=false
## set startup profile
ARG MVN_PROFILE=main
ARG TZ=Asia/Shanghai
ARG INSTALL_FONTS=false
ARG INSTALL_FFMPEG=false
ARG USE_JEMALLOC=false

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