#!/usr/bin/env bash

set -xe
if [ "${CHANGE_SOURCE:-false}" = true ]; then
    if [ -f /etc/apt/sources.list ]; then
        apt_file=/etc/apt/sources.list
    elif [ -f /etc/apt/sources.list.d/debian.sources ]; then
        apt_file=/etc/apt/sources.list.d/debian.sources
    fi
    sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' "$apt_file"
    # export http_proxy=http://192.168.44.11:1080
    # export https_proxy=http://192.168.44.11:1080
fi
# ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
# echo $TZ >/etc/timezone
apt-get -yq update
apt-get install -yq --no-install-recommends apache2 php php-curl php-gd php-ldap php-mbstring php-mysql php-xml php-zip php-cli php-json curl ca-certificates unzip libapache2-mod-php
# Clear dev deps
apt-get clean
apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/log/lastlog /var/log/faillog

chmod +x /app/docker-entrypoint.sh
sed -i '1 i ServerName 127.0.0.1' /etc/apache2/apache2.conf
a2enmod rewrite

cat >/etc/apache2/sites-enabled/000-default.conf <<EOF
<VirtualHost *:80>
    DocumentRoot /app/zentaopms/www

    <Directory />
        Options FollowSymLinks
        AllowOverride All
	Require all granted
    </Directory>
    ErrorLog /var/log/apache2/zentao_error_log
    CustomLog /var/log/apache2/zentao_access_log combined
</VirtualHost>
EOF

# lib_dir=$(ls -d /usr/lib/php/????????/)
# php_dir=$(ls -d /etc/php/*/)
# cp -avf /app/ioncube_loader_lin_7.0.so "$lib_dir"
# echo "zend_extension = ${lib_dir}ioncube_loader_lin_7.0.so" >"${php_dir}"apache2/conf.d/00-ioncube.ini
# echo "zend_extension = ${lib_dir}ioncube_loader_lin_7.0.so" >"${php_dir}"cli/conf.d/00-ioncube.ini

# https://www.zentao.net/dl/zentao/18.9/ZenTaoPMS-18.9-php7.2_7.4.zip
# https://www.zentao.net/dl/zentao/18.12/ZenTaoPMS-18.12-php8.1.zip
download_url="https://www.zentao.net/dl/zentao/${ZT_VERSION}/ZenTaoPMS-${ZT_VERSION}-php8.1.zip"
curl -fLo zentao.zip "$download_url"
unzip -q zentao.zip
rm -f zentao.zip
php -v
