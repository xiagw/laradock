#!/bin/bash

_default_key() {
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

_issue_cert() {
    c=0
    # email="email=$(date | md5sum | cut -c 1-6)@deploy.sh"
    # acme.sh --register-account -m $email
    while read -r domain; do
        [[ -z $domain || -d $LE_CONFIG_HOME/$domain ]] && continue
        c=$((c + 1))
        acme.sh --issue -w /var/www/html -d "$domain"
        if [[ $c = 1 ]]; then
            acme.sh --install-cert -d "$domain" --key-file $ssl_dir/default.key --fullchain-file $ssl_dir/default.crt
        else
            acme.sh --install-cert -d "$domain" --key-file $ssl_dir/"$domain".key --fullchain-file $ssl_dir/"$domain".crt
        fi
    done <$ssl_dir/domains.txt
}

ssl_dir="/etc/nginx/conf.d/ssl"

_default_key

_issue_cert

html_dir=/var/www/html
[ -d $html_dir/.well-known/acme-challenge ] || mkdir -p $html_dir/.well-known/acme-challenge
[ -d $html_dir/tp ] || mkdir -p $html_dir/tp
[ -d $html_dir/static ] || mkdir -p $html_dir/static
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
