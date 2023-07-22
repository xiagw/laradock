#!/bin/sh

_build() {
    if [ "${CHANGE_SOURCE}" = true ] || [ "${IN_CHINA}" = true ]; then
        sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/' /etc/apk/repositories
    fi

    apk update
    apk upgrade
    apk add --no-cache bash curl shadow openssl openssh-client
    touch /var/log/messages

    # Set upstream conf and remove the default conf
    echo "upstream php-upstream { server ${PHP_UPSTREAM_CONTAINER}:${PHP_UPSTREAM_PORT}; }" >/etc/nginx/php-upstream.conf
    # rm /etc/nginx/conf.d/default.conf

    ## install acme.sh
    email="email=$(date | md5sum | cut -c 1-6)@deploy.sh"
    curl -fL https://get.acme.sh | sh -s "$email"
    ln -s /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
    # crontab -l | grep acme.sh | sed 's#> /dev/null#>/proc/1/fd/1 2>/proc/1/fd/2#' | crontab -
}

_onbuild() {
    # groupmod -g 1000 nginx
    # usermod -u 1000 nginx
    if [ -f "$me_path"/nginx.conf ]; then
        cp -vf "$me_path"/nginx.conf /etc/nginx/
    fi
    if [ -f "$me_path"/run.sh ]; then
        cp -vf "$me_path"/run.sh /docker-entrypoint.d/
        sed -i 's/\r//g' /docker-entrypoint.d/run.sh
        chmod +x /docker-entrypoint.d/run.sh
    fi
}

main() {
    set -xe
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="${me_path}/${me_name}.log"

    case $1 in
    --onbuild)
        _onbuild
        ;;
    *)
        _build
        ;;
    esac
}

main "$@"