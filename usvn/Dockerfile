# FROM php:5.6-apache
# COPY svn-apache.conf /etc/apache2/sites-enabled/000-default.conf
# RUN apt-get update \
#   && apt-get install -y --force-yes libapache2-mod-svn subversion \
#   && a2enmod dav \
#   && a2enmod dav_fs \
#   && a2enmod rewrite \
#   && a2enmod authz_svn \
#   && a2enmod dav_svn \
#   && mkdir /var/www/usvn \
#   && cd /var/www/usvn \
#   && curl -L https://github.com/usvn/usvn/archive/1.0.7.tar.gz | tar --strip-components=1 -xz \
#   && mkdir /var/www/usvn/files && chmod a+rwx /var/www/usvn/files \
#   && chown -R www-data:www-data /var/www/

# FROM kempkensteffen/usvn
# RUN set -xe \
#   && sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list \
#   && apt-get update \
#   && apt-get install -y --force-yes rsync lsyncd openssh-client \
#   && chown -R www-data:www-data /var/www/ \
#   ## Clear dev deps
#   && apt-get clean \
#   && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
#   && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/log/lastlog /var/log/faillog
# COPY ./run.sh /
# RUN chmod +x /run.sh
# CMD [ "/run.sh" ]

FROM php:7.3-apache
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -xe \
  && sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list \
  && apt-get update \
  && apt-get install -y vim libapache2-mod-svn subversion rsync lsyncd openssh-client locales inotify-tools \
  && grep -q '^en_US.UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen \
  && locale-gen \
  && a2enmod dav \
  && a2enmod dav_fs \
  && a2enmod rewrite \
  && a2enmod authz_svn \
  && a2enmod dav_svn
RUN curl -sSLo /tmp/usvn.tgz https://github.com/usvn/usvn/archive/1.0.10.tar.gz \
  && tar --strip-components=1 -C /tmp/ -xzf /tmp/usvn.tgz \
  && mkdir -p /var/www/usvn_src \
  && cp -af /tmp/src/* /var/www/usvn_src/ \
  && mkdir -p /var/www/svn_commit \
  && chown -R www-data:www-data /var/www/ \
  ## Clear dev deps
  && apt-get clean \
  && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/log/lastlog /var/log/faillog

WORKDIR /root
COPY ./etc/ /etc/
COPY ./root/ /root/

RUN set -xe \
  && chmod +x /root/run.sh \
  && printf 'export LANG="en_US.UTF-8"\nalias ll="ls -al --color"\n' >>/root/.bashrc

## On Host:
## echo 'fs.inotify.max_user_watches = 99999999' | sudo tee -a /etc/sysctl.d/99-sysctl.conf
## sudo sysctl -p

CMD [ "/root/run.sh" ]
