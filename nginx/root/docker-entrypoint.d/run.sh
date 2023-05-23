#!/bin/bash

_default_key() {
    ssl_dir="/etc/nginx/conf.d/ssl"
    default_key="$ssl_dir/default.key"
    default_csr="$ssl_dir/default.csr"
    default_crt="$ssl_dir/default.crt"
    dhparams=$ssl_dir/dhparams.pem

    [ -d "$ssl_dir" ] || mkdir -p "$ssl_dir"

    if [ ! -f "$default_crt" ]; then
        openssl genrsa -out "$default_key" 2048
        openssl req -new -key "$default_key" -out "$default_csr" -subj "/CN=default/O=default/C=UK"
        openssl x509 -req -days 365 -in "$default_csr" -signkey "$default_key" -out "$default_crt"
    fi

    if [[ ! -f $dhparams || $(stat -c %s $dhparams) -lt 1500 ]]; then
        openssl dhparam -dsaparam -out $dhparams 4096
    fi

    chown nginx:nginx $ssl_dir/*.key /var/log/nginx
    chmod 600 $ssl_dir/*.key
}

_default_key

html_dir=/var/www/html
[ -d $html_dir/.well-known/acme-challenge ] || mkdir -p $html_dir/.well-known/acme-challenge
[ -f $html_dir/index.html ] || date >>$html_dir/index.html

## nginx 4xx 5xx
if [ ! -f $html_dir/4xx.html ]; then
    echo 'Error page: 4xx' >>$html_dir/4xx.html
fi
if [ ! -f $html_dir/5xx.html ]; then
    echo 'Error page: 5xx' >>$html_dir/5xx.html
fi


# Start crond in background
crond -l 2 -b
