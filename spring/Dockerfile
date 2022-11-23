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
    && apt-get update && apt-get install -y --no-install-recommends wget  fontconfig  \
    && fc-cache --force \
    && wget -q --referer=http://www.flyh6.com/ http://cdn.flyh6.com/docker/fonts-2022.tar \
    && tar -xvf fonts-2022.tar -C /usr/share \
    && rm -f fonts-2022.tar; \
    fi; \
    if [ "$INSTALL_FFMPEG" = true ]; then \
    apt-get update && apt-get install -y --no-install-recommends ffmpeg; \
    fi; \
    sed -i 's/SSLv3\,\ TLSv1\,\ TLSv1\.1\,//g' /usr/local/openjdk-8/jre/lib/security/java.security || true; \
    # apt-get autoremove -y \
    apt-get clean all \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

USER 1000
EXPOSE 8080 8081 8082
# volume /data

CMD ["/app/run.sh"]
