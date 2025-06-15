#!/usr/bin/env bash
# set -o pipefail

log() {
    echo "$(date +'%F_%T') - [repl] $*"
}

wait_mysql() {
    while ! $mysqladmin_cli ping -h"localhost" --silent; do
        sleep 0.1
    done
}

create_mysql_config() {
    local mysql_conf="/root/.my.cnf"
    cat >"$mysql_conf" <<EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF
}

if [ "$(id -u)" -ne 0 ]; then
    exit
fi

case "$MYSQL_REPL_MODE" in
s | single) exit 0 ;;
esac

# Get MySQL version
mysql_version=$(mysqld --version | awk '{print $3}' | cut -d. -f1)
if [ -z "$mysql_version" ]; then
    log "MySQL version not found, exiting"
    exit 1
fi
if [ "$mysql_version" -lt 8 ]; then
    ## 初始时 root@localhost 密码为空
    if mysql -e "select 1" >/dev/null 2>&1; then
        log "Initial password for root@localhost"
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
    fi
fi

create_mysql_config

mysql_cli="mysql --defaults-file=/root/.my.cnf -f"
mysqladmin_cli="mysqladmin --defaults-file=/root/.my.cnf"

# 检查是否是首次初始化
if [ ! -f "/var/lib/mysql/ibdata1" ]; then
    log "First time MySQL initialization detected, waiting for setup..."
    wait_mysql
    log "MySQL first ping successful, waiting for restart..."

    # 记录第一次成功ping的时间
    first_success_time=$(date +%s)
    restart_detected=false

    # 等待检测到重启或超时
    while true; do
        if ! $mysqladmin_cli ping -h"localhost" --silent; then
            log "MySQL restart detected, waiting for it to come back up..."
            restart_detected=true
            break
        fi

        current_time=$(date +%s)
        if [ $((current_time - first_success_time)) -gt 15 ]; then
            log "No restart detected within 15 seconds, something might be wrong"
            break
        fi
        sleep 0.1
    done

    log "MySQL restart detected, waiting for it to come back up..."
    restart_detected=true

    if [ "$restart_detected" = true ]; then
        wait_mysql
        log "MySQL initialization completed"
    fi
else
    # 如果已经初始化过，只需要等待MySQL启动
    wait_mysql
fi

log "Starting MySQL replication setup..."

# Default values
REPL_USER=${MYSQL_REPL_USER:-repl}
REPL_PASSWORD=${MYSQL_REPL_PASSWORD:-replpass}
MASTER_HOST=${MYSQL_MASTER_HOST:-mysql1}

$mysql_cli <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
CREATE USER IF NOT EXISTS '${REPL_USER}'@'%' IDENTIFIED BY '${REPL_PASSWORD}';
GRANT REPLICATION SLAVE ON *.* TO '${REPL_USER}'@'%';
FLUSH PRIVILEGES;
EOF

case "$MYSQL_REPL_MODE" in
m2s | s2r | p2s | master2slave | source2replica | primary2secondary)
    if [ "$mysql_version" -lt 8 ]; then
        case "$MYSQL_ROLE" in
        master | source | primary)
            # Master doesn't need special setup
            ;;
        slave | replica | secondary)
            # MySQL 5.7 syntax
            $mysql_cli <<EOF
CHANGE MASTER TO
MASTER_HOST='${MASTER_HOST}',
MASTER_USER='${REPL_USER}',
MASTER_PASSWORD='${REPL_PASSWORD}',
MASTER_AUTO_POSITION=1;

STOP SLAVE IO_THREAD, SQL_THREAD;
EOF
            sleep 2
            $mysql_cli <<EOF
START SLAVE IO_THREAD, SQL_THREAD USER='${REPL_USER}' PASSWORD='${REPL_PASSWORD}';
EOF
            sleep 2
            $mysql_cli <<EOF
SHOW SLAVE STATUS\G
EOF
            ;;
        esac

    else

        case "$MYSQL_ROLE" in
        master | source | primary)
            # Master doesn't need special setup
            ;;
        slave | replica | secondary)
            # MySQL 8.0 syntax
            $mysql_cli <<EOF
CHANGE REPLICATION SOURCE TO
SOURCE_HOST='${MASTER_HOST}',
SOURCE_USER='${REPL_USER}',
SOURCE_PASSWORD='${REPL_PASSWORD}',
SOURCE_AUTO_POSITION=1,
GET_SOURCE_PUBLIC_KEY=1;

STOP REPLICA IO_THREAD, SQL_THREAD;
EOF
            sleep 2
            $mysql_cli <<EOF
START REPLICA USER='${REPL_USER}' PASSWORD='${REPL_PASSWORD}';
EOF
            sleep 2
            $mysql_cli <<EOF
SHOW REPLICA STATUS\G
EOF
            ;;
        esac
    fi
    ;;

m2m | s2s | p2p | master2master | source2source | primary2primary)
    # Wait for the other master to be ready
    while ! $mysqladmin_cli ping -h"${MASTER_HOST}" --silent; do
        log "Waiting for other master ${MASTER_HOST} to be ready..."
        sleep 5
    done

    if [ "$mysql_version" -lt 8 ]; then
        # MySQL 5.7 syntax
        $mysql_cli <<EOF
CHANGE MASTER TO
MASTER_HOST='${MASTER_HOST}',
MASTER_USER='${REPL_USER}',
MASTER_PASSWORD='${REPL_PASSWORD}',
MASTER_AUTO_POSITION=1;

STOP SLAVE IO_THREAD, SQL_THREAD;
EOF
        sleep 2
        $mysql_cli <<EOF
START SLAVE IO_THREAD, SQL_THREAD USER='${REPL_USER}' PASSWORD='${REPL_PASSWORD}';
EOF
        sleep 2
        $mysql_cli <<EOF
SHOW SLAVE STATUS\G
EOF
    else
        # MySQL 8.0 syntax
        $mysql_cli <<EOF
CHANGE REPLICATION SOURCE TO
SOURCE_HOST='${MASTER_HOST}',
SOURCE_USER='${REPL_USER}',
SOURCE_PASSWORD='${REPL_PASSWORD}',
SOURCE_AUTO_POSITION=1,
GET_SOURCE_PUBLIC_KEY=1;

STOP REPLICA IO_THREAD, SQL_THREAD;
EOF
        sleep 2
        $mysql_cli <<EOF
START REPLICA USER='${REPL_USER}' PASSWORD='${REPL_PASSWORD}';
EOF
        sleep 2
        $mysql_cli <<EOF
SHOW REPLICA STATUS\G
EOF

    fi
    ;;
esac
