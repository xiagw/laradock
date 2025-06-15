#!/usr/bin/env bash

grant2table() {
    local tables=(
        transportation_ad_log
        transportation_admin_log
        transportation_gold_log
    )

    while read -r line; do
        if [[ " ${tables[*]} " =~ \ ${line}\  ]]; then
            echo "GRANT SELECT, INSERT ON defaultdb.$line TO 'defaultdb'@'%';"
        elif [[ "$line" == *"_loggg" ]]; then
            echo "GRANT SELECT, INSERT ON defaultdb.$line TO 'defaultdb'@'%';"
        else
            echo "GRANT ALL PRIVILEGES ON defaultdb.$line TO 'defaultdb'@'%';"
        fi
    done < <(mysql defaultdb -Ne 'show tables;') | mysql -v -f
}

restore_db() {
    ls "$backup_path"/*.sql
    read -rp "Input file name: " read_sql_file
    db=${read_sql_file#*.full.}
    db=${db%.sql}
    echo "Input file is: $read_sql_file"
    echo "Get db name: $db"
    $mysql_bin -e "create database if not exists $db;"
    $mysql_bin "${db}" <"$read_sql_file"
}

backup_user_perm() {
    ## backup user and grants
    user_list=$backup_path/user.list.txt
    user_perm=$backup_path/user.perm.sql
    $mysql_bin -Ne 'select user,host from mysql.user' >"$user_list"
    while read -r user host; do
        $mysql_bin -Ne "show grants for \`${user}\`@'${host}';"
    done <"$user_list" >"$user_perm"
}

backup_db() {
    ## backup single/multiple databases
    databases="$1"
    if [[ -z "$databases" ]]; then
        databases="$(
            $mysql_bin -Ne 'show databases' |
                grep -vE 'information_schema|performance_schema|^sys$|^mysql$'
        )"
    fi

    backup_time="$(date +%s)"

    for db in $databases; do
        backup_file="$backup_path/${backup_time}.full.${db}.sql"
        if $mysql_bin "$db" -e 'select now()' >/dev/null; then
            $mysql_dump "$db" -r "$backup_file"
            echo "$(date) - $backup_file finish" | tee -a "$me_log"
        else
            echo "database $db not exists."
        fi
    done
}

clean_backup() {
    ## remove backup before 1 year
    find "$backup_path" -mtime +180 -type f -delete
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

    ## check mysql version
    mysql_bin="mysql --defaults-file=$HOME/.my.cnf"
    mysql_dump="mysqldump --defaults-file=$HOME/.my.cnf --set-gtid-purged=OFF --events --routines"

    my_ver=$($mysql_bin -Ne "select version();" | cut -d. -f1)
    if [ "$my_ver" -lt 8 ]; then
        mysql_dump+=" --master-data=2"
    else
        mysql_dump+=" --source-data=2"
    fi

    case "$1" in
    restore)
        restore_db "$@"
        ;;
    backup)
        backup_user_perm
        backup_db "$@"
        ;;
    clean)
        clean_backup
        ;;
    esac
}

main "$@"

# rsync -a /var/lib/mysql/*-bin.?????? $backup_path/
