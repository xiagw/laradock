#!/usr/bin/env bash

name_script="$(basename "$0")"
path_script="$(dirname "$(readlink -f "$0")")"
path_backup="$path_script"
log_backup="$path_backup/${name_script}.log"

# rsync -a /var/lib/mysql/*-bin.?????? $path_backup/
for i in *.full.*.sql; do
    echo "$i"
    db=${i#*.full.}
    db=${db%.sql}
    mysql -e "create database if not exists $db;"
    mysql "${db}" <"$i"
done
