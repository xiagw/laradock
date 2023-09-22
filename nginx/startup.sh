#!/bin/bash

ssl_dir="/etc/nginx/conf.d/ssl"
[ -d "$ssl_dir" ] || mkdir -p "$ssl_dir"
if [ ! -f $ssl_dir/default.pem ]; then
    openssl genrsa -out "$ssl_dir/default.key" 2048
    openssl req -new -key "$ssl_dir/default.key" -out "$ssl_dir/default.csr" -subj "/CN=default/O=default/C=CN"
    openssl x509 -req -days 3650 -in "$ssl_dir/default.csr" -signkey "$ssl_dir/default.key" -out "$ssl_dir/default.pem"
fi

if [ ! -f $ssl_dir/dhparams.pem ]; then
    openssl dhparam -dsaparam -out $ssl_dir/dhparams.pem 4096
fi

# chmod 0644 /etc/logrotate.d/nginx

html_path=/var/www/html
log_path=/var/log/nginx
[ -f $html_path/index.html ] || date >>$html_path/index.html
if [ ! -d $html_path/.well-known/acme-challenge ]; then
    mkdir -p $html_path/.well-known/acme-challenge
fi
if [ ! -d $html_path ]; then
    mkdir -p $html_path
fi
chown -R 1000:1000 $html_path
chmod 600 $ssl_dir/*.key
chown -R nginx $ssl_dir/*.key $log_path

## php upstream
if ping -c 2 php-fpm >/dev/null 2>&1; then
    echo 'upstream upstream-php { server php-fpm:9000; }' >/etc/nginx/conf.d/upstream-php.conf
else
    echo 'upstream upstream-php { server 127.0.0.1:9000; }' >/etc/nginx/conf.d/upstream-php.conf
fi

## nginx 4xx 5xx
if [ ! -f $html_path/4xx.html ]; then
    echo 'Error page: 4xx' >>$html_path/4xx.html
fi
if [ ! -f $html_path/5xx.html ]; then
    echo 'Error page: 5xx' >>$html_path/5xx.html
fi

## remove log files / 自动清理超过15天的旧日志文件
while [ -d $log_path ]; do
    find $log_path -type f -iname '*.log' -ctime +15 -print0 | xargs -0 rm -f
    sleep 1d
done &

# Start crond in background
crond -l 2 -b

# Start nginx in foreground
# exec nginx
