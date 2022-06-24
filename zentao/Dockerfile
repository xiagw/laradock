FROM debian:10-slim

LABEL maintainer="xiagw <fxiaxiaoyu@gmail.com>"

# If you're in China, or you need to change sources, will be set CHANGE_SOURCE to true in .env.
ARG CHANGE_SOURCE=true
RUN if [ ${CHANGE_SOURCE} = true ]; then \
  # Change application source from deb.debian.org to aliyun source
  sed -i 's/deb.debian.org/mirrors.aliyun.com/' /etc/apt/sources.list && \
  sed -i 's/security.debian.org/mirrors.aliyun.com/' /etc/apt/sources.list && \
  sed -i 's/security-cdn.debian.org/mirrors.aliyun.com/' /etc/apt/sources.list \
  ;fi
#####################################
# Set Timezone
#####################################
ARG TZ=UTC
ENV TZ ${TZ}
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN set -xe \
  && apt-get -yq update \
  && apt-get install -yq --no-install-recommends apache2 php php-curl php-gd \
    php-ldap php-mbstring php-mysql php-xml php-zip php-cli php-json curl \
    unzip libapache2-mod-php \
  # Clear dev deps
  && apt-get clean \
  && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/log/lastlog /var/log/faillog

ARG ZENTAO_VERSION=17.1

WORKDIR /app

COPY docker-entrypoint.sh .
# RUN rm -rf /etc/apache2/sites-enabled/000-default.conf /var/lib/mysql/*
COPY config/apache.conf /etc/apache2/sites-enabled/000-default.conf
COPY config/ioncube_loader_lin_7.0.so /usr/lib/php/20151012/ioncube_loader_lin_7.0.so
COPY config/00-ioncube.ini /etc/php/7.0/apache2/conf.d/
COPY config/00-ioncube.ini /etc/php/7.0/cli/conf.d/

WORKDIR /var/www

RUN chmod +x /app/docker-entrypoint.sh \
  && sed -i '1 i ServerName 127.0.0.1' /etc/apache2/apache2.conf \
  && a2enmod rewrite \
  # https://www.zentao.net/dl/zentao/17.1/ZenTaoPMS.17.1.php7.1.zip
  # https://www.zentao.net/dl/zentao/17.1/ZenTaoPMS.17.1.php7.2_7.4.zip
  #curl http://dl.cnezsoft.com/zentao/${ZENTAO_VERSION}/ZenTaoPMS.${ZENTAO_VERSION}.stable.zip -o /var/www/zentao.zip && \
  && curl https://www.zentao.net/dl/zentao/${ZENTAO_VERSION}/ZenTaoPMS.${ZENTAO_VERSION}.php7.2_7.4.zip -o zentao.zip \
  && unzip -q zentao.zip \
  && rm zentao.zip

EXPOSE 80

VOLUME /app/zentaopms

ENTRYPOINT ["/app/docker-entrypoint.sh"]
