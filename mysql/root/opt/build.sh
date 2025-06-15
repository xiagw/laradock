#!/usr/bin/env bash

set -xe

cat >>/root/.bashrc <<'EOF'
export LANG=C.UTF-8
echo "[client]" >/root/.my.cnf
echo "password=${MYSQL_ROOT_PASSWORD}" >>/root/.my.cnf
chmod 600 /root/.my.cnf
EOF

# Add auto-start replication script to MySQL entrypoint
chmod +x /opt/*.sh
if [ -f /usr/local/bin/docker-entrypoint.sh ]; then
    sed -i '/if .* _is_sourced.* then/i (exec /opt/repl.sh) &' /usr/local/bin/docker-entrypoint.sh
elif [ -f /entrypoint.sh ]; then
    sed -i '/echo ".Entrypoint. MySQL Docker Image/i (exec /opt/repl.sh) &' /entrypoint.sh
else
    echo "not found entrypoint file"
fi

ln -snf /usr/share/zoneinfo/"$TZ" /etc/localtime
echo "$TZ" >/etc/timezone
chown -R mysql:root /var/lib/mysql/
chmod o-rw /var/run/mysqld

if [ -f /etc/my.cnf ]; then
    sed -i '/skip-host-cache/d' /etc/my.cnf
fi

## 单机模式 MYSQL_REPL_MODE=single，不需要复制参数
## 主从模式 MYSQL_REPL_MODE=m2s，根据 MYSQL_ROLE=master MYSQL_ROLE=slave 设置参数
## 主主模式 MYSQL_REPL_MODE=m2m，根据 MYSQL_ROLE=master1 MYSQL_ROLE=master2 设置参数

my_ver=$(mysqld --version | awk '{print $3}' | cut -d. -f1)
my_cnf=/etc/mysql/conf.d/my.cnf

# Generate base configuration
cat >$my_cnf <<'EOF'
[mysqld]
host_cache_size=0
explicit_defaults_for_timestamp
tls_version=TLSv1.2,TLSv1.3
character-set-server=utf8mb4
# lower_case_table_names = 1
myisam_recover_options = FORCE,BACKUP
max_allowed_packet = 128M
max_connect_errors = 1000000
skip-name-resolve

# Connection timeout settings
wait_timeout = 28800
interactive_timeout = 28800

# Performance settings
max_connections = 2048
open_files_limit = 65535
slow_query_log = 1
long_query_time = 1

EOF

# Add version-specific configurations
if [ "$my_ver" -lt 8 ]; then
    # MySQL 5.7 specific configurations
    cat >>$my_cnf <<'EOF'
sql-mode="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER"
default-authentication-plugin=mysql_native_password
character-set-client-handshake = FALSE

EOF
else
    # MySQL 8.0 specific configurations
    cat >>$my_cnf <<'EOF'
sql-mode="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO"

EOF
fi

# Handle replication configuration based on MYSQL_REPL_MODE
case "$MYSQL_REPL_MODE" in
s | single)
    # Single instance mode, only basic server_id
    cat >>$my_cnf <<'EOF'
server_id = 1
read_only = 0
EOF
    ;;
m2s | s2r | p2s | master2slave | source2replica | primary2secondary)
    # Master-Slave replication mode
    # Common replication settings
    cat >>$my_cnf <<'EOF'
# Binary log settings
log_bin = log-bin
log_bin_index = log-bin
binlog_format = ROW
binlog_row_image = MINIMAL
sync_binlog = 1
max_binlog_size = 1024M
binlog_cache_size = 4M
binlog_checksum = NONE

# GTID settings
gtid_mode = ON
enforce_gtid_consistency = ON

# Binlog filters
binlog_ignore_db = mysql
binlog_ignore_db = test
binlog_ignore_db = information_schema

# Relay log settings
relay_log = mysql-relay-bin
relay_log_index = mysql-relay-bin.index
relay_log_recovery = ON
relay_log_purge = 1
relay_log_space_limit = 0
sync_relay_log = 1
EOF

    # Add version-specific replication settings
    if [ "$my_ver" -lt 8 ]; then
        cat >>$my_cnf <<'EOF'
# MySQL 5.7 replication settings
log_slave_updates = ON
slave_preserve_commit_order = 1
master_info_repository = TABLE
relay_log_info_repository = TABLE
sync_relay_log_info = 1
slave_net_timeout = 60
expire_logs_days = 30
transaction_write_set_extraction = XXHASH64
EOF
    else
        cat >>$my_cnf <<'EOF'
# MySQL 8.0 replication settings
log_replica_updates = ON
replica_preserve_commit_order = 1
replica_net_timeout = 60
binlog_expire_logs_seconds = 2592000  # 30 days
EOF
    fi

    # Add role-specific settings
    case "$MYSQL_ROLE" in
    master | source | primary)
        cat >>$my_cnf <<'EOF'
######## Master-Slave replication (source)
server_id = 1
read_only = 0
EOF
        ;;
    slave | replica | secondary)
        cat >>$my_cnf <<'EOF'
######## Master-Slave replication (replica)
server_id = 2
read_only = 1

# Replication filters
replicate_ignore_db = mysql
replicate_ignore_db = test
replicate_ignore_db = information_schema
replicate_ignore_db = easyschedule
replicate_wild_ignore_table = easyschedule.%
EOF
        ;;
    esac
    ;;
m2m | s2s | p2p | master2master | source2source | primary2primary)
    # Master-Master replication mode
    # Common replication settings
    cat >>$my_cnf <<'EOF'
# Binary log settings
log_bin = log-bin
log_bin_index = log-bin
binlog_format = ROW
binlog_row_image = MINIMAL
sync_binlog = 1
max_binlog_size = 1024M
binlog_cache_size = 4M
binlog_checksum = NONE

# GTID settings
gtid_mode = ON
enforce_gtid_consistency = ON

# Common filters
binlog_ignore_db = mysql
binlog_ignore_db = test
binlog_ignore_db = information_schema
replicate_ignore_db = mysql
replicate_ignore_db = test
replicate_ignore_db = information_schema

# Relay log settings
relay_log = mysql-relay-bin
relay_log_index = mysql-relay-bin.index
relay_log_recovery = ON
relay_log_purge = 1
relay_log_space_limit = 0
sync_relay_log = 1
#
EOF

    # Add version-specific replication settings
    if [ "$my_ver" -lt 8 ]; then
        cat >>$my_cnf <<'EOF'
# MySQL 5.7 replication settings
log_slave_updates = ON
slave_preserve_commit_order = 1
master_info_repository = TABLE
relay_log_info_repository = TABLE
sync_relay_log_info = 1
slave_net_timeout = 60
expire_logs_days = 30
transaction_write_set_extraction = XXHASH64
#
EOF
    else
        cat >>$my_cnf <<'EOF'
# MySQL 8.0 replication settings
log_replica_updates = ON
replica_preserve_commit_order = 1
replica_net_timeout = 60
## 30 days
binlog_expire_logs_seconds = 2592000
#
EOF
    fi

    # Add role-specific settings
    case "$MYSQL_ROLE" in
    master1 | source1 | primary1)
        cat >>$my_cnf <<'EOF'
######## Master-Master replication (source 1)
server_id = 1
read_only = 0
auto_increment_offset = 1
auto_increment_increment = 2
EOF
        ;;
    master2 | source2 | primary2)
        cat >>$my_cnf <<'EOF'
######## Master-Master replication (source 2)
server_id = 2
read_only = 0
auto_increment_offset = 2
auto_increment_increment = 2
EOF
        ;;
    esac
    ;;
*)
    # Default single instance mode
    cat >>$my_cnf <<'EOF'
server_id = 1
read_only = 0
EOF
    ;;
esac

chmod 0644 $my_cnf
