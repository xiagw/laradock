#!/usr/bin/env bash

set -xe

while true; do
    backup_bin=/usr/bin/xtrabackup
    backup_path=/backup/xtrabackup
    backup_base="$backup_path/base-$(date +%U)"

    if [ -f "$backup_base"/xtrabackup_logfile ]; then
        echo "$(date), backup incremental...begin"
        $backup_bin \
            --backup \
            --host=mysql \
            --user=root \
            --password="${MYSQL_ROOT_PASSWORD-}" \
            --target-dir="$backup_path"/inc-"$(date +%s)" \
            --incremental-basedir="$backup_base"
        echo "$(date), backup incremental end."
    else
        echo "$(date), backup full...begin"
        $backup_bin \
            --backup \
            --datadir=/var/lib/mysql/ \
            --host=mysql \
            --user=root \
            --password="${MYSQL_ROOT_PASSWORD-}" \
            --target-dir="$backup_base"
        echo "$(date), backup full end."
    fi
done &

wait
