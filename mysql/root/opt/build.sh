#!/usr/bin/env bash

set -xe

ln -snf /usr/share/zoneinfo/"$TZ" /etc/localtime
echo "$TZ" >/etc/timezone
chown -R mysql:root /var/lib/mysql/
chmod o-rw /var/run/mysqld

# me_name="$(basename "$0")"
# me_path="$(dirname "$(readlink -f "$0")")"
# me_log="$me_path/${me_name}.log"

my_cnf=/etc/mysql/conf.d/my.cnf
my_ver=$(mysqld --version | awk '{print $3}' | cut -d. -f1)

# Generate base configuration
cat >$my_cnf <<'EOF'
[mysqld]
host_cache_size=0
# initialize-insecure=0
explicit_defaults_for_timestamp
tls_version=TLSv1.2,TLSv1.3
character-set-server=utf8mb4
# lower_case_table_names = 1
myisam_recover_options = FORCE,BACKUP
max_allowed_packet = 128M
max_connect_errors = 1000000
sync_binlog = 1
log_bin = log-bin
log_bin_index = log-bin
skip-name-resolve
read_only = 0
# binlog_do_db = default
binlog_ignore_db = mysql
binlog_ignore_db = test
binlog_ignore_db = information_schema
replicate_ignore_db = mysql
replicate_ignore_db = test
replicate_ignore_db = information_schema
replicate_ignore_db = easyschedule
replicate_wild_ignore_table = easyschedule.%
# log_replica_updates

#############################################
# query_cache_type = 0
# query_cache_size = 0
# innodb_log_files_in_group = 2
# innodb_log_file_size = 2560M
# tmp_table_size = 32M
# max_heap_table_size = 64M
max_connections = 2048
# thread_cache_size = 50
open_files_limit = 65535
# table_definition_cache = 2048
# table_open_cache = 2048
# innodb_flush_method = O_DIRECT
# innodb_redo_log_capacity = 2560M
# innodb_flush_log_at_trx_commit = 1
# innodb_file_per_table = 1
# innodb_buffer_pool_size = 1G
# log_queries_not_using_indexes = 0
slow_query_log = 1
long_query_time = 1
# innodb_stats_on_metadata = 0
EOF

# Add version-specific configurations
if [ "$my_ver" -lt 8 ]; then
    # MySQL 5.7 specific configurations
    cat >>$my_cnf <<'EOF'
sql-mode="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER"
default-authentication-plugin=mysql_native_password
character-set-client-handshake = FALSE
binlog_format = ROW
EOF
else
    # MySQL 8.0 specific configurations
    cat >>$my_cnf <<'EOF'
sql-mode="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO"
EOF
fi

case "$MYSQL_REPLICATION" in
single | master2slave)
    cat >>$my_cnf <<'EOF'
server_id = 1
auto_increment_offset = 1
auto_increment_increment = 1
EOF
    ;;
master1)
    cat >>$my_cnf <<'EOF'
######## M2M replication (master to master, source to source)
server_id = 1
## 主键奇数列
auto_increment_offset = 1
## 递增步长 2
auto_increment_increment = 2
EOF
    ;;
master2)
    cat >>$my_cnf <<'EOF'
######## M2M replication (master to master, source to source)
server_id = 2
## 主键偶数列
auto_increment_offset = 2
## 递增步长 2
auto_increment_increment = 2
EOF
    ;;
esac

chmod 0644 $my_cnf

if [ -f /etc/my.cnf ]; then
    sed -i '/skip-host-cache/d' /etc/my.cnf
fi

# sed -i '/docker_create_db_directories "$@"/a echo root-here' /usr/local/bin/docker-entrypoint.sh
cat >>/root/.bashrc <<'EOF'
export LANG=C.UTF-8
echo "[client]" >/root/.my.cnf
echo "password=${MYSQL_ROOT_PASSWORD}" >>/root/.my.cnf
chmod 600 /root/.my.cnf
EOF

chmod +x /opt/*.sh
