#!/usr/bin/env bash

set -xe
/usr/bin/xtrabackup --backup \
    --datadir=/var/lib/mysql/ \
    --target-dir=/backup/xtrabackup \
    --host=mysql \
    --user=root \
    --password=${MYSQL_ROOT_PASSWORD}