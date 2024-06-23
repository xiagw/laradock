#!/usr/bin/env bash

set -xe

backup_bin=/usr/bin/xtrabackup
backup_path=/backup/xtrabackup
backup_base="$backup_path/base-$(date +%U)"

if [ -f "$backup_base"/xtrabackup_logfile ]; then
    $backup_bin \
        --backup \
        --host=mysql \
        --user=root \
        --password="${MYSQL_ROOT_PASSWORD-}" \
        --target-dir="$backup_path"/inc-"$(date +%s)" \
        --incremental-basedir="$backup_path"/"$backup_base"
else
    [ -d "$backup_base" ] || mkdir -p "$backup_base"
    chown 999:999 "$backup_base"
    $backup_bin \
        --backup \
        --datadir=/var/lib/mysql/ \
        --host=mysql \
        --user=root \
        --password="${MYSQL_ROOT_PASSWORD-}" \
        --target-dir="$backup_base"
fi
