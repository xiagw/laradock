#!/usr/bin/env bash

grant2table() {
    local tables=(
        transportation_ad_log
        transportation_admin_log
        transportation_gold_log
    )

    local tmp_sql
    tmp_sql=$(mktemp)

    mysql defaultdb -Ne 'show tables;' | while read -r line; do
        if [[ " ${tables[*]} " =~ \ ${line}\  ]]; then
            echo "GRANT SELECT, INSERT ON defaultdb.$line TO 'defaultdb'@'%';"
        elif [[ "$line" == *"_loggg" ]]; then
            echo "GRANT SELECT, INSERT ON defaultdb.$line TO 'defaultdb'@'%';"
        else
            echo "GRANT ALL PRIVILEGES ON defaultdb.$line TO 'defaultdb'@'%';"
        fi
    done >"$tmp_sql"

    mysql -v <"$tmp_sql"
    rm -f "$tmp_sql"
}

## 启动时自定义授权指定表
# grant2table
