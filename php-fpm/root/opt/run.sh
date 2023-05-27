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

_set_lsyncd() {
    id_file="/etc/lsyncd/id_ed25519"
    lsyncd_conf=/etc/lsyncd/lsyncd.conf.lua
    if [ ! -f "$id_file" ]; then
        _msg "new ssh key."
        ssh-keygen -t ed25519 -f "$id_file" -N ''
    fi
    cat >$HOME/.ssh/config <<EOF
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 6
    IdentityFile $id_file
    StrictHostKeyChecking no
    GSSAPIAuthentication no
    Compression yes
EOF
    lsyncd $lsyncd_conf
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
html_path=/var/www/html
[ -d /var/lib/php/sessions ] && chmod -R 777 /var/lib/php/sessions
[ -d /run/php ] || mkdir -p /run/php
[ -d $html_path ] || mkdir $html_path
[ -f $html_path/index.html ] || date >>$html_path/index.html

## create runtime for ThinkPHP
while [ -d $html_path ]; do
    for dir in $html_path/ $html_path/tp/ "$html_path"/tp/*/; do
        [ -d "$dir" ] || continue
        ## ThinkPHP 5.1
        [[ -f "${dir}"think && -d ${dir}thinkphp && -d ${dir}application ]] && need_runtime=1
        ## ThinkPHP 6.0
        [[ -f "${dir}"think && -d ${dir}thinkphp && -d ${dir}app ]] && need_runtime=1
        if [[ "$need_runtime" -eq 1 ]]; then
            run_dir="${dir}runtime"
            [[ -d "$run_dir" ]] || mkdir "$run_dir"
            dir_owner="$(stat -t -c %U "$run_dir")"
            [[ "$dir_owner" == www-data ]] || chown -R www-data:www-data "$run_dir"
        fi
    done
    sleep 600
done &

## remove runtime log files
while [ -d $html_path ]; do
    for dir in $html_path/ $html_path/tp/ "$html_path"/tp/*/; do
        [ -d "$dir" ] || continue
        find "${dir}runtime" -type f -iname '*.log' -ctime +5 -print0 | xargs -t --null rm -f
    done
    sleep 86400
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
    exec tail -f $html_path/index.html &
    pids="${pids} $!"
fi

# _set_lsyncd &

_check_jemalloc &

## 识别中断信号，停止进程
trap _kill HUP INT PIPE QUIT TERM

## 保持容器运行
wait
