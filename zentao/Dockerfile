FROM debian:10-slim

LABEL maintainer="xiagw <fxiaxiaoyu@gmail.com>"

# If you're in China, or you need to change sources, will be set CHANGE_SOURCE to true in .env.
ARG CHANGE_SOURCE=true
# Set Timezone
ARG TZ=UTC
ARG ZENTAO_VERSION=18.10
ENV TZ ${TZ}

RUN set -xe; \
  if [ ${CHANGE_SOURCE} = true ]; then \
  sed -i -e 's/deb.debian.org/mirrors.aliyun.com/' -e 's/security.debian.org/mirrors.aliyun.com/' -e 's/security-cdn.debian.org/mirrors.aliyun.com/' /etc/apt/sources.list; \
  fi; \
  ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone; \
  apt-get -yq update; \
  apt-get install -yq --no-install-recommends apache2 php php-curl php-gd \
    php-ldap php-mbstring php-mysql php-xml php-zip php-cli php-json \
    curl ca-certificates unzip libapache2-mod-php; \
  # Clear dev deps
  apt-get clean; \
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/log/lastlog /var/log/faillog

WORKDIR /var/www
COPY root/ /
RUN chmod +x /app/docker-entrypoint.sh \
  && sed -i '1 i ServerName 127.0.0.1' /etc/apache2/apache2.conf \
  && a2enmod rewrite \
  # https://www.zentao.net/dl/zentao/18.9/ZenTaoPMS-18.9-php7.2_7.4.zip
  && curl -Lo zentao.zip https://www.zentao.net/dl/zentao/${ZENTAO_VERSION}/ZenTaoPMS-${ZENTAO_VERSION}-php7.2_7.4.zip \
  && unzip -q zentao.zip \
  && rm -f zentao.zip

EXPOSE 80

VOLUME /app/zentaopms

ENTRYPOINT ["/app/docker-entrypoint.sh"]
