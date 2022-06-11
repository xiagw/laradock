#!/usr/bin/env bash

name_script="$(basename "$0")"
path_script="$(dirname "$(readlink -f "$0")")"
echo "$path_script" >/dev/null
path_backup="/backup"
log_backup="$path_backup/${name_script}.log"

## check permission
if [ ! -w "$path_backup" ]; then
    echo "permission denied to '$path_backup', exit."
    exit 1
fi
## check mysql version
ver_number=$(mysql --version | awk '{print $3}' | sed 's/\.//g')
if [[ $ver_number -le 8025 ]]; then
    mysql_dump='mysqldump -E -R --triggers --master-data=2'
else
    mysql_dump='mysqldump -E -R --triggers --source-data=2'
fi
## backup single/multiple databases
backup_time="$(date +%s)"
db_name="$1"
if [[ -z "$db_name" ]]; then
    dbs="$(mysql -Ne 'show databases' | grep -vE '^default$|information_schema|mysql|performance_schema|^sys$')"
else
    dbs="$db_name"
fi
for db in $dbs; do
    backup_file="$path_backup/${backup_time}.full.${db}.sql"
    if mysql "$db" -e 'select now()' >/dev/null; then
        $mysql_dump "$db" -r "$backup_file"
        echo "$(date) - $backup_file finish" | tee -a "$log_backup"
    else
        echo "database $db not exists."
    fi
done

# rsync -a /var/lib/mysql/*-bin.?????? $path_backup/
