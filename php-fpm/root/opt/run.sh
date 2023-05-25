#!/bin/bash

# set -x

_kill() {
    echo "[INFO] Receive SIGTERM, kill $pids"
    for pid in $pids; do
        kill "$pid"
        wait "$pid"
    done
}

_check_jemalloc() {
    sleep 60
    for pid in $pids; do
        if grep -q "/proc/$pid/smaps"; then
            echo "PID $pid using jemalloc..."
        else
            echo "PID $pid not use jemalloc"
        fi
    done
}

## index for default site
pre_path=/var/www
html_path=$pre_path/html
[ -d /var/lib/php/sessions ] && chmod -R 777 /var/lib/php/sessions
[ -d /run/php ] || mkdir -p /run/php
[ -d $html_path ] || mkdir $html_path
[ -f $html_path/index.html ] || date >>$html_path/index.html

## create runtime for ThinkPHP
while [ -d $html_path ]; do
    for dir in $html_path/ $html_path/tp/ $html_path/tp/*/; do
        [ -d $dir ] || continue
        if [[ -f "$dir"/think && -d $dir/thinkphp && -d $dir/application ]]; then
            run_dir="$dir/runtime"
            [[ -d "$run_dir" ]] || mkdir "$run_dir"
            [[ "$(stat -t -c %u $run_dir)" == 1000 ]] || chown -R 1000:1000 "$run_dir"
        fi
    done
    sleep 60
done &

if [ -f /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 ]; then
    export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
fi
# 1. lsof -Pn -p $(pidof mariadbd) | grep jemalloc，配置正确的话会有jemalloc.so的输出；
# 2. cat /proc/$(pidof mariadbd)/smaps | grep jemalloc，和上述命令有类似的输出。

## start php-fpm
for i in /usr/sbin/php-fpm*; do
    [ -x "$i" ] && $i -F &
    pids="${pids} $!"
done
## start nginx
if command -v nginx && nginx -t; then
    exec nginx -g "daemon off;" &
    pids="${pids} $!"
## start apache
elif command -v apachectl && apachectl -t; then
    exec apachectl -k start -D FOREGROUND &
    pids="${pids} $!"
else
    exec tail -f /var/www/html/index.html &
fi

_check_jemalloc &

## 识别中断信号，停止进程
trap _kill HUP INT PIPE QUIT TERM

wait
