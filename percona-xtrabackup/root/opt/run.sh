#!/usr/bin/env bash

set -xe
if [ -f /backup/xtrabackup/base/xtrabackup_logfile ]; then
    /usr/bin/xtrabackup \
        --backup \
        --target-dir=/backup/xtrabackup/inc-"$(date +%s)" \
        --incremental-basedir=/backup/xtrabackup/base \
        --host=mysql \
        --user=root \
        --password="${MYSQL_ROOT_PASSWORD}"
else
    /usr/bin/xtrabackup \
        --backup \
        --datadir=/var/lib/mysql/ \
        --target-dir=/backup/xtrabackup/base \
        --host=mysql \
        --user=root \
        --password="${MYSQL_ROOT_PASSWORD-}"
fi
