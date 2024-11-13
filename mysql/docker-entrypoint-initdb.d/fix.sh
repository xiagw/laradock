#!/usr/bin/env bash

printf "[client]\npassword=%s\n" "${MYSQL_ROOT_PASSWORD}" >/root/.my.cnf
chmod 600 /root/.my.cnf

grant2table() {
    tmp_sql=$(mktemp)
    mysql defaultdb -Ne 'show tables;' | while read -r line; do
        case "$line" in
        transportation_ad_log | transportation_admin_log | transportation_gold_log)
            echo "GRANT SELECT, INSERT ON defaultdb.$line TO 'defaultdb'@'%';"
            ;;
        *_loggg)
            echo "GRANT SELECT, INSERT ON defaultdb.$line TO 'defaultdb'@'%';"
            ;;
        *)
            echo "GRANT ALL PRIVILEGES ON defaultdb.$line TO 'defaultdb'@'%';"
            ;;
        esac
    done >"$tmp_sql"

    mysql -v <"$tmp_sql"
    rm -f "$tmp_sql"
}
