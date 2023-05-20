#!/bin/bash

set -xe

if [ "$IN_CHINA" = true ] || [ "$CHANGE_SOURCE" = true ]; then
    sed -i 's/archive.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
fi
## preesed tzdata, update package index, upgrade packages and install needed software
truncate -s0 /tmp/preseed.cfg
echo "tzdata tzdata/Areas select Asia" >>/tmp/preseed.cfg
echo "tzdata tzdata/Zones/Asia select Shanghai" >>/tmp/preseed.cfg
debconf-set-selections /tmp/preseed.cfg

rm -f /etc/timezone /etc/localtime

apt-get update -y
apt-get install -y --no-install-recommends apt-utils tzdata
apt-get install -y --no-install-recommends locales

grep -q '^en_US.UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen
locale-gen en_US.UTF-8

case "$LARADOCK_PHP_VERSION" in
8.*)
    :
    ;;
*)
    apt-get install -y --no-install-recommends software-properties-common
    add-apt-repository ppa:ondrej/php
    apt-get install -y --no-install-recommends php"${PHP_VER}"-mcrypt
    ;;
esac

apt-get upgrade -y
apt-get install -y --no-install-recommends \
    php"${LARADOCK_PHP_VERSION}" \
    php"${LARADOCK_PHP_VERSION}"-redis \
    php"${LARADOCK_PHP_VERSION}"-mongodb \
    php"${LARADOCK_PHP_VERSION}"-imagick \
    php"${LARADOCK_PHP_VERSION}"-fpm \
    php"${LARADOCK_PHP_VERSION}"-gd \
    php"${LARADOCK_PHP_VERSION}"-mysql \
    php"${LARADOCK_PHP_VERSION}"-xml \
    php"${LARADOCK_PHP_VERSION}"-xmlrpc \
    php"${LARADOCK_PHP_VERSION}"-bcmath \
    php"${LARADOCK_PHP_VERSION}"-gmp \
    php"${LARADOCK_PHP_VERSION}"-zip \
    php"${LARADOCK_PHP_VERSION}"-soap \
    php"${LARADOCK_PHP_VERSION}"-curl \
    php"${LARADOCK_PHP_VERSION}"-bz2 \
    php"${LARADOCK_PHP_VERSION}"-mbstring \
    php"${LARADOCK_PHP_VERSION}"-msgpack \
    php"${LARADOCK_PHP_VERSION}"-sqlite3
# php"${LARADOCK_PHP_VERSION}"-process \
# php"${LARADOCK_PHP_VERSION}"-pecl-mcrypt  replace by  php"${LARADOCK_PHP_VERSION}"-libsodium

if [ "$INSTALL_APACHE" = true ]; then
    apt-get install -y --no-install-recommends \
        apache2 libapache2-mod-fcgid \
        libapache2-mod-php"${LARADOCK_PHP_VERSION}"
    sed -i -e '1 i ServerTokens Prod' \
        -e '1 i ServerSignature Off' \
        -e '1 i ServerName www.example.com' \
        /etc/apache2/sites-available/000-default.conf
else
    apt-get install -y --no-install-recommends nginx
fi

apt-get clean all && rm -rf /tmp/*
