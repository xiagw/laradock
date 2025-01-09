#!/usr/bin/env bash

_kill() {
    echo "receive SIGTERM, kill ${pids[*]}"
    for pid in "${pids[@]}"; do
        kill "$pid"
        wait "$pid"
    done
}

[ "$DEBUG" ] && set -x
## 安装禅道 / 升级禅道
if [ -f /app/zentaopms/VERSION ]; then
    zt_ver=$(cat /app/zentaopms/VERSION)
else
    upgrade=true
fi
if [ -f /var/www/zentaopms/VERSION ]; then
    ver_docker=$(cat /var/www/zentaopms/VERSION)
fi
if [ "${zt_ver:-app}" != "${ver_docker:-docker}" ]; then
    upgrade=true
fi
if [ "$upgrade" = true ]; then
    cp -af /var/www/zentaopms/* /app/zentaopms
fi
chmod -R 777 /app/zentaopms/www/data /app/zentaopms/tmp
chmod 777 /app/zentaopms/www /app/zentaopms/config
chmod -R a+rx /app/zentaopms/bin/*
chown -R www-data:www-data /app/zentaopms

pids=()
# /etc/init.d/apache2 start
# tail -f /var/log/apache2/zentao_error_log
php -v
echo "Zentao Version: $ver_docker"
apache2ctl -D FOREGROUND &
pids+=("$!")

## 识别中断信号，停止 java 进程
trap _kill HUP INT PIPE QUIT TERM SIGWINCH

wait
