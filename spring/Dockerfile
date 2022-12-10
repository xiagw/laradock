FROM openjdk:8u332 as RUNTIME
## set startup profile
ARG MVN_PROFILE=test
## Set Timezone
ARG TZ=Asia/Shanghai
ENV TZ=$TZ
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
## set java opts
ARG JAVA_OPTS='java -Xms256m -Xmx384m'
ENV JAVA_OPTS="$JAVA_OPTS"
## install fonts
ARG INSTALL_FONTS=true
## install ffmpeg
ARG INSTALL_FFMPEG=false

RUN if [ "$INSTALL_FONTS" = true ]; then \
    sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends fontconfig \
    && fc-cache --force \
    && curl -LO --referer http://www.flyh6.com/ http://cdn.flyh6.com/docker/fonts-2022.tar \
    && tar -xvf fonts-2022.tar -C /usr/share \
    && rm -f fonts-2022.tar; \
    fi; \
    if [ "$INSTALL_FFMPEG" = true ]; then \
    apt-get update && apt-get install -y --no-install-recommends ffmpeg; \
    fi; \
    sed -i 's/SSLv3\,\ TLSv1\,\ TLSv1\.1\,//g' /usr/local/openjdk-8/jre/lib/security/java.security || true; \
    curl -Lo /opt/run.sh https://gitee.com/xiagw/deploy.sh/raw/main/conf/dockerfile/run.sh; \
    chmod +x /opt/run.sh; \
    # apt-get autoremove -y \
    apt-get clean all \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# COPY ./jar_file/ .
RUN chown -R 1000:1000 /app \
    # && touch "/app/profile.${MVN_PROFILE}" \
    && [ -f run.sh ] && chmod +x run.sh || true

USER 1000
EXPOSE 8080 8081 8082
# volume /data

CMD ["/opt/run.sh"]
