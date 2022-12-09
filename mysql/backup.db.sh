#!/usr/bin/env bash

# set -xe
main() {
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="$me_path/${me_name}.log"

    path_backup="/data/java-static/bydq/sql"
    ## check permission
    if [ ! -w "$path_backup" ]; then
        echo "permission denied to '$path_backup', exit."
        return 1
    fi
    ## .my.cnf
    if [ -f $me_path/.my.cnf ]; then
        mysql_cnf="--defaults-extra-file=$me_path/.my.cnf"
    elif [ -f $HOME/.my.cnf ]; then
        mysql_cnf="--defaults-extra-file=$HOME/.my.cnf"
    else
        mysql_cnf="--defaults-extra-file=/var/lib/mysql/.my.cnf"
    fi
    ## check mysql version
    mysql_bin="mysql $mysql_cnf"
    mysql_dump="mysqldump $mysql_cnf --set-gtid-purged=OFF -E -R --triggers"
    ver_number=$(mysql --version | awk '{print $3}' | sed 's/\.//g')
    if [[ $ver_number -le 8025 ]]; then
        mysql_dump="$mysql_dump --master-data=2"
    else
        mysql_dump="$mysql_dump --source-data=2"
    fi
    ## backup single/multiple databases
    backup_time="$(date +%Y%m%d)"
    if [[ -z "$1" ]]; then
        dbs="$($mysql_bin -Ne 'show databases' | grep -vE '^default$|information_schema|performance_schema|^sys$|^mysql$')"
    else
        dbs="$1"
    fi
    for db in $dbs; do
        backup_file="$path_backup/${db}${backup_time}.sql"
        if mysql "$db" -e 'select now()' >/dev/null; then
            $mysql_dump "$db" -r "$backup_file"
            echo "$(date) - $backup_file finish" | tee -a "$me_log"
        else
            echo "database $db not exists."
        fi
    done
}

main "$@"

## chmod +x /root/backup.db.sh
## 01 03 * * * /root/backup.db.sh
