#!/usr/bin/env bash

_restore_db() {
    ls "$backup_path"/*.sql
    read -rp "Input file name: " read_sql_file
    db=${read_sql_file#*.full.}
    db=${db%.sql}
    echo "Input file is: $read_sql_file"
    echo "Get db name: $db"
    $mysql_bin -e "create database if not exists $db;"
    $mysql_bin "${db}" <"$read_sql_file"
}

main() {
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="$me_path/${me_name}.log"
    backup_path="/backup"

    ## check /backup permission
    if [ -w "$backup_path" ]; then
        echo "[OK] $backup_path is writable."
    else
        echo "[Fail] permission denied to $backup_path, exit."
        return 1
    fi
    ## .my.cnf
    if [ -f "$me_path/.my.cnf" ]; then
        mysql_cnf="--defaults-extra-file=$me_path/.my.cnf"
    elif [ -f "$HOME/.my.cnf" ]; then
        mysql_cnf="--defaults-extra-file=$HOME/.my.cnf"
    else
        mysql_cnf="--defaults-extra-file=/var/lib/mysql/.my.cnf"
    fi
    ## check mysql version
    mysql_bin="mysql $mysql_cnf"
    mysql_dump="mysqldump $mysql_cnf --set-gtid-purged=OFF -E -R --triggers"
    if mysql --version | grep -q "mysql.*Ver.*Distrib"; then
        ver_number=$(mysql --version | awk '{print int($5)}')
    elif mysql --version | grep -q "mysql.*Ver.*Linux.*Community"; then
        ver_number=$(mysql --version | awk '{print int($3)}')
    fi
    if [[ $ver_number -le 8 ]]; then
        mysql_dump="$mysql_dump --master-data=2"
    else
        mysql_dump="$mysql_dump --source-data=2"
    fi
    ## backup user and grants
    user_list=$backup_path/user.list.txt
    user_perm=$backup_path/user.perm.sql
    mysql -Ne 'select user,host from mysql.user' >"$user_list"
    while read -r line; do
        read -r -a user_host <<<$line
        mysql -Ne "show grants for \`${user_host[0]}\`@'${user_host[1]}';" >>"$user_perm"
    done <"$user_list"
    ## restore database
    if [[ "$1" == restore ]]; then
        _restore_db
        return 0
    fi
    ## backup single/multiple databases
    if [[ -z "$1" ]]; then
        dbs="$($mysql_bin -Ne 'show databases' | grep -vE 'information_schema|performance_schema|^sys$|^mysql$')"
    else
        dbs="$1"
    fi
    backup_time="$(date +%s)"
    for db in $dbs; do
        backup_file="$backup_path/${backup_time}.full.${db}.sql"
        if $mysql_bin "$db" -e 'select now()' >/dev/null; then
            $mysql_dump "$db" -r "$backup_file"
            echo "$(date) - $backup_file finish" | tee -a "$me_log"
        else
            echo "database $db not exists."
        fi
    done
}

main "$@"

# rsync -a /var/lib/mysql/*-bin.?????? $backup_path/
