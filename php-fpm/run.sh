#!/usr/bin/env bash

## catch the TERM signal and exit cleanly
trap "exit 0" HUP INT PIPE QUIT TERM

[ -d /var/lib/php/sessions ] && chmod -R 777 /var/lib/php/sessions
[ -d /run/php ] || mkdir -p /run/php
[ -d /var/www/html ] || mkdir /var/www/html
[ -f /var/www/html/index.html ] || date >>/var/www/html/index.html

## start php-fpm
for i in /usr/sbin/php-fpm*; do
    [ -x "$i" ] && $i
done

pre_path=/var/www
html_path=$pre_path/html
## create runtime for ThinkPHP
while true; do
    for dir in $html_path/ $html_path/tp/ $html_path/tp/*/; do
        [ -d $dir ] || continue
        if [[ -f "$dir"/think && -d $dir/thinkphp && -d $dir/application ]]; then
            run_dir="$dir/runtime"
            [[ -d "$run_dir" ]] || mkdir "$run_dir"
            [[ "$(stat -t -c %u $run_dir)" == 33 ]] || chown -R 33:33 "$run_dir"
        fi
    done
    sleep 60
done &
## schedule task
for file in $pre_path/*/task.sh; do
    if [[ -f $file ]]; then
        cd "${file##*/}" && bash $file
    fi
done &

if nginx -t &>/dev/null; then
    ## start nginx
    exec nginx -g "daemon off;"
elif apachectl -t &>/dev/null; then
    ## start apache
    exec apachectl -k start -D FOREGROUND
else
    exec tail -f /var/www/html/index.html
fi
