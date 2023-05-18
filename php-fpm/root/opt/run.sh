#!/bin/bash

# set -x

_kill() {
    echo "[INFO] Receive SIGTERM, kill $pids"
    for pid in $pids; do
        kill "$pid"
        wait "$pid"
    done
}

## index for default site
[ -d /var/lib/php/sessions ] && chmod -R 777 /var/lib/php/sessions
[ -d /run/php ] || mkdir -p /run/php
[ -d /var/www/html ] || mkdir /var/www/html
[ -f /var/www/html/index.html ] || date >>/var/www/html/index.html

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

## start php-fpm
for i in /usr/sbin/php-fpm*; do
    [ -x "$i" ] && $i -F &
    pids="${pids} $!"
done

## schedule task
for file in $pre_path/*/task.sh; do
    if [[ -f $file ]]; then
        cd "${file##*/}" && bash $file
    fi
done &

if command -v nginx && nginx -t; then
    ## start nginx
    exec nginx -g "daemon off;" &
    pids="${pids} $!"
elif command -v apachectl && apachectl -t; then
    ## start apache
    exec apachectl -k start -D FOREGROUND &
    pids="${pids} $!"
else
    exec tail -f /var/www/html/index.html &
fi

## 识别中断信号，停止进程
trap _kill HUP INT PIPE QUIT TERM

wait
