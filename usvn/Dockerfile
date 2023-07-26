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

FROM php:7.4-apache
## for apt to be noninteractive
ENV DEBIAN_FRONTEND noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN true
ENV TIME_ZOME Asia/Shanghai

WORKDIR /var/www
COPY ./root/opt/build.sh /opt/
RUN bash /opt/build.sh

COPY ./root/ /
CMD ["/bin/bash", "/opt/run.sh" ]

## On Host:
## echo 'fs.inotify.max_user_watches = 99999999' | sudo tee -a /etc/sysctl.d/99-sysctl.conf
## sudo sysctl -p
## cat /proc/sys/fs/inotify/max_user_watches

