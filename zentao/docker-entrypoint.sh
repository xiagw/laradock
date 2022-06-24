#!/usr/bin/env bash

[ "$DEBUG" ] && set -x

if [ ! -f /app/zentaopms/VERSION ] || [ "$(cat /app/zentaopms/VERSION)" != "$(cat /var/www/zentaopms/VERSION)" ]; then
  cp -a /var/www/zentaopms/* /app/zentaopms
fi
chmod -R 777 /app/zentaopms/www/data /app/zentaopms/tmp
chmod 777 /app/zentaopms/www /app/zentaopms/config
chmod -R a+rx /app/zentaopms/bin/*
chown -R www-data:www-data /app/zentaopms

# /etc/init.d/apache2 start
# tail -f /var/log/apache2/zentao_error_log
apache2ctl -D FOREGROUND
