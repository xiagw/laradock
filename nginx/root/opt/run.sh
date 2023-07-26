#!/bin/bash

_default_key() {
    default_key="$ssl_dir/default.key"
    default_csr="$ssl_dir/default.csr"
    default_pem="$ssl_dir/default.pem"
    dhparams=$ssl_dir/dhparams.pem

    if [ -f "$default_pem" ] && [ -f $default_pem ]; then
        echo "Found $default_key and $default_pem, skip create."
    else
        echo "Not found $default_key and $default_pem, create..."
        openssl genrsa -out "$default_key" 2048
        openssl req -new -key "$default_key" -out "$default_csr" -subj "/CN=default/O=default/C=CN"
        openssl x509 -req -days 365 -in "$default_csr" -signkey "$default_key" -out "$default_pem"
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
    if test -f $ssl_dir/domains.txt; then
        echo "Found $ssl_dir/domains.txt, run acme.sh"
    else
        echo "Not found $ssl_dir/domains.txt, skip acme.sh"
        return
    fi
    while read -r domain; do
        [[ -z $domain ]] && continue
        c=$((c + 1))

        if [ -d "${LE_CONFIG_HOME}/$domain" ]; then
            ## renew cert / 续签证书
            acme.sh --renew -d "$domain"
        else
            ## create cert / 创建证书
            acme.sh --issue -d "$domain" -w /var/www/html
        fi
        if [[ $c = 1 ]]; then
            ## The First domain to be defalut.key / 第一个（或只有一个）域名作为默认域名
            acme.sh --install-cert -d "$domain" --key-file $ssl_dir/default.key --fullchain-file $ssl_dir/default.pem
        else
            ## The others / 其他域名使用域名的名称作为文件名
            acme.sh --install-cert -d "$domain" --key-file $ssl_dir/"$domain".key --fullchain-file $ssl_dir/"$domain".pem
        fi
    done <$ssl_dir/domains.txt
}

main() {
    ssl_dir="/etc/nginx/conf.d/ssl"
    [ -d "$ssl_dir" ] || mkdir -p "$ssl_dir"

    _default_key

    _issue_cert

    html_dir=/var/www/html
    log_dir=/app/log/nginx
    [ -d $html_dir/.well-known/acme-challenge ] || mkdir -p $html_dir/.well-known/acme-challenge
    [ -d $html_dir/tp ] || mkdir -p $html_dir/tp
    [ -d $html_dir/static ] || mkdir -p $html_dir/static
    [ -f $html_dir/index.html ] || date >>$html_dir/index.html

    [ -d $log_dir ] || mkdir -p $log_dir
    ## log dir 权限设置
    chown nginx:nginx $log_dir

    [ -d $html_dir ] || mkdir -p $html_dir
    [ -f $html_dir/index.html ] || date >$html_dir/index.html

    ## nginx 4xx 5xx
    printf 'error page 5xx' >/usr/share/nginx/html/50x.html
    if [ ! -f $html_dir/4xx.html ]; then
        printf 'Error page: 4xx' >$html_dir/4xx.html
    fi
    if [ ! -f $html_dir/5xx.html ]; then
        printf 'Error page: 5xx' >$html_dir/5xx.html
    fi

    ## remove log files / 自动清理超过7天的旧日志文件
    while [ -d $log_dir ]; do
        find $log_dir -type f -iname '*.log' -ctime +7 -print0 | xargs -t -0 rm -f
        sleep 86400
    done &

    # Start crond in background / 开启定时任务 crond
    if command -v crond; then
        crond -l 2 -b
    fi
}

main "$@"
