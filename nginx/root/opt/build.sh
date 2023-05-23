#!/bin/sh

set -xe

if [ "${CHANGE_SOURCE}" = true ]; then
    sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/' /etc/apk/repositories
fi

apk update
apk upgrade
apk add --no-cache openssl bash curl
touch /var/log/messages

apk --no-cache add shadow
groupmod -g 1000 nginx
usermod -u 1000 nginx

# Set upstream conf and remove the default conf
echo "upstream php-upstream { server ${PHP_UPSTREAM_CONTAINER}:${PHP_UPSTREAM_PORT}; }" >/etc/nginx/php-upstream.conf
# rm /etc/nginx/conf.d/default.conf

sed -i 's/\r//g' /docker-entrypoint.d/run.sh
chmod +x /docker-entrypoint.d/run.sh

## install acme.sh
email="email=$(date | md5sum | cut -c 1-6)@deploy.sh"
curl -fL https://get.acme.sh | sh -s "$email"