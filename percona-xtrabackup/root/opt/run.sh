#!/usr/bin/env bash

set -xe
if [ -f /backup/xtrabackup/xtrabackup_logfile ]; then
    /usr/bin/xtrabackup \
        --backup \
        --target-dir=/backup/inc-"$(date +%s)" \
        --incremental-basedir=/backup/xtrabackup \
        --host=mysql \
        --user=root \
        --password="${MYSQL_ROOT_PASSWORD}"
else
    /usr/bin/xtrabackup --backup \
        --datadir=/var/lib/mysql/ \
        --target-dir=/backup/xtrabackup \
        --host=mysql \
        --user=root \
        --password="${MYSQL_ROOT_PASSWORD-}"
fi
