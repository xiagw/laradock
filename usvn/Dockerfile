# FROM php:5.6-apache
FROM kempkensteffen/usvn

RUN set -xe \
  && sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list \
  && apt-get update \
  && apt-get install -y --force-yes rsync lsyncd openssh-client \
  ## Clear dev deps
  && apt-get clean \
  && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/log/lastlog /var/log/faillog
COPY ./run.sh /
RUN chmod +x /run.sh
CMD [ "/run.sh" ]
