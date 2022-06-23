FROM php:7.3-apache
RUN set -xe \
  && sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list \
  && apt-get update \
  && apt-get install -y --force-yes vim libapache2-mod-svn subversion rsync lsyncd openssh-client locales \
  && grep -q '^en_US.UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen \
  && locale-gen \
  && a2enmod dav \
  && a2enmod dav_fs \
  && a2enmod rewrite \
  && a2enmod authz_svn \
  && a2enmod dav_svn \
  && cd /tmp \
  && curl -sSL https://github.com/usvn/usvn/archive/1.0.10.tar.gz | tar --strip-components=1 -xz \
  && mkdir /var/www/usvn_src \
  && cp -af /tmp/src/* /var/www/usvn_src/ \
  && chown -R www-data:www-data /var/www/ \
  ## Clear dev deps
  && apt-get clean \
  && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/log/lastlog /var/log/faillog
WORKDIR /root
COPY svn-apache.conf /etc/apache2/sites-enabled/000-default.conf
COPY ./run.sh .
RUN chmod +x /root/run.sh

CMD [ "/root/run.sh" ]
