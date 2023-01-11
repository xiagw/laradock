#!/bin/bash

ssl_dir="/etc/nginx/conf.d/ssl"
[ -d "$ssl_dir" ] || mkdir -p "$ssl_dir"

if [ ! -f $ssl_dir/default.crt ]; then
    openssl genrsa -out "$ssl_dir/default.key" 2048
    openssl req -new -key "$ssl_dir/default.key" -out "$ssl_dir/default.csr" -subj "/CN=default/O=default/C=UK"
    openssl x509 -req -days 365 -in "$ssl_dir/default.csr" -signkey "$ssl_dir/default.key" -out "$ssl_dir/default.crt"
    chmod 644 $ssl_dir/default.key
fi

if [ ! -f $ssl_dir/dhparams.pem ]; then
    openssl dhparam -dsaparam -out $ssl_dir/dhparams.pem 4096
fi

chmod 0644 /etc/logrotate.d/nginx
chown 33:0 /var/log/nginx

## /var/www/html
[ -d /var/www/html ] || mkdir -p /var/www/html
[ -f /var/www/html/index.html ] || date >>/var/www/html/index.html

# Start crond in background
crond -l 2 -b

# Start nginx in foreground
exec nginx
