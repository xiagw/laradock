#!/bin/bash

# set -x


_msg() {
    echo "[$(date)], $*"
}

_kill() {
    _msg "receive SIGTERM, kill $pids"
    for pid in $pids; do
        kill "$pid"
        wait "$pid"
    done
}

_check_jemalloc() {
    sleep 5
    for pid in $pids; do
        if grep -q jemalloc "/proc/$pid/smaps"; then
            _msg "PID $pid using jemalloc..."
        else
            _msg "PID $pid not use jemalloc"
        fi
    done
}

case "$LARADOCK_PHP_VERSION" in
8.*)
    _msg "disable jemalloc."
    ;;
*)
    _msg "enable jemalloc..."
    if [ -f /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 ]; then
        export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
    fi
    # 1. lsof -Pn -p $(pidof mariadbd) | grep jemalloc，配置正确的话会有jemalloc.so的输出；
    # 2. cat /proc/$(pidof mariadbd)/smaps | grep jemalloc，和上述命令有类似的输出。
    ;;
esac

php -v

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
            [[ "$(stat -t -c %U $run_dir)" == www-data ]] || chown -R www-data:www-data "$run_dir"
        fi
    done
    sleep 60
done &

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
## 保持容器运行
wait
