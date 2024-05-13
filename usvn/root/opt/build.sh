#!/usr/bin/env bash

set -xe
## mirror for china
if [[ ${CHANGE_SOURCE:-false} = true ]]; then
    sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
    url_usvn=http://oss.flyh6.com/d/usvn.tar.gz
else
    url_usvn=https://github.com/usvn/usvn/archive/1.0.10.tar.gz
fi
preseed=/tmp/preseed.cfg
truncate -s0 $preseed
(
    echo "tzdata tzdata/Areas select Asia"
    echo "tzdata tzdata/Zones/Asia select Shanghai"
) >>$preseed
debconf-set-selections $preseed

rm -f /etc/timezone /etc/localtime

apt-get update -yqq
apt-get install -yqq apt-utils tzdata vim libapache2-mod-svn subversion rsync lsyncd openssh-client locales inotify-tools

if ! grep '^en_US.UTF-8' /etc/locale.gen; then
    echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen
fi
locale-gen en_US.UTF-8

a2enmod dav dav_fs rewrite authz_svn dav_svn

mkdir -p /var/www/usvn_src
curl -fsSLo - "$url_usvn" | tar --strip-components=1 -C /tmp/ -xz
rsync -av /tmp/src/ /var/www/usvn_src/
chown -R www-data:www-data /var/www/
sed -i -e "78 a ServerName svn.mydomain.com\n" /etc/apache2/apache2.conf

## Clear dev dep
apt-get clean
apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/log/lastlog /var/log/faillog

(
    echo 'export LANG="en_US.UTF-8"'
    echo 'alias ll="ls -al --color"'
) >>/root/.bashrc
