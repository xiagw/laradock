#!/usr/bin/env bash

# set -xe

## backup mysql, UTC 03 hour
while true; do
    if [[ "$(date -u +%H)" == 03 ]]; then
        /opt/backup.sh
    fi
    sleep 60
done &

## startup mysqld
# /usr/sbin/mysqld