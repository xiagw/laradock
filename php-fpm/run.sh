#!/usr/bin/env bash

## catch the TERM signal and exit cleanly
trap "exit 0" HUP INT PIPE QUIT TERM

[ -d /var/lib/php/sessions ] && chmod -R 777 /var/lib/php/sessions
[ -d /var/www/public ] || mkdir /var/www/public
[ -d /run/php ] || mkdir -p /run/php
[ -f /var/www/public/index.html ] || date >/var/www/public/index.html

## start php-fpm
for i in /usr/sbin/php-fpm*; do
    [ -x "$i" ] && $i
done

## start task
[ -f /var/www/schedule.sh ] && bash /var/www/schedule.sh &

if nginx -t &>/dev/null; then
    ## start nginx
    exec nginx -g "daemon off;"
elif apachectl -t &>/dev/null; then
    ## start apache
    exec apachectl -k start -D FOREGROUND
else
    exec tail -f /var/www/public/index.html
fi
