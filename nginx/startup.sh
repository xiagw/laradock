#!/bin/bash

ssl_dir="/etc/nginx/conf.d/ssl"
[ -d "$ssl_dir" ] || mkdir -p "$ssl_dir"

if [ ! -f $ssl_dir/default.crt ]; then
    openssl genrsa -out "$ssl_dir/default.key" 2048
    openssl req -new -key "$ssl_dir/default.key" -out "$ssl_dir/default.csr" -subj "/CN=default/O=default/C=CN"
    openssl x509 -req -days 365 -in "$ssl_dir/default.csr" -signkey "$ssl_dir/default.key" -out "$ssl_dir/default.pem"
    chown nginx $ssl_dir/default.key
fi

if [ ! -f $ssl_dir/dhparams.pem ]; then
    openssl dhparam -dsaparam -out $ssl_dir/dhparams.pem 4096
fi

# chmod 0644 /etc/logrotate.d/nginx
chown 1000:0 /var/log/nginx

## /var/www/html
[ -d /var/www/html/.well-known/acme-challenge ] || mkdir -p /var/www/html/.well-known/acme-challenge
if [ ! -d /var/www/html ]; then
    mkdir -p /var/www/html
    chown -R 1000:1000 /var/www/html
fi
[ -f /var/www/html/index.html ] || date >>/var/www/html/index.html

## nginx 4xx 5xx
if [ ! -f /var/www/html/4xx.html ]; then
    echo 'Error page: 4xx' >>/var/www/html/4xx.html
fi
if [ ! -f /var/www/html/5xx.html ]; then
    echo 'Error page: 5xx' >>/var/www/html/5xx.html
fi

## remove log files / 自动清理超过7天的旧日志文件
while [ -d /var/log/nginx ]; do
    find /var/log/nginx -type f -iname '*.log' -ctime +15 -print0 | xargs -t -0 rm -f
    sleep 1d
done &

# Start crond in background
crond -l 2 -b

# Start nginx in foreground
# exec nginx
