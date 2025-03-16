#!/usr/bin/env bash

set -xe

ln -snf /usr/share/zoneinfo/"$TZ" /etc/localtime
echo "$TZ" >/etc/timezone
chown -R mysql:root /var/lib/mysql/
chmod o-rw /var/run/mysqld

# me_name="$(basename "$0")"
me_path="$(dirname "$(readlink -f "$0")")"
# me_log="$me_path/${me_name}.log"

my_cnf=/etc/mysql/conf.d/my.cnf
my_ver=$(mysqld --version | awk '{print $3}' | cut -d. -f1)
if [ "$my_ver" -gt 5 ]; then
    cp -f "$me_path"/my.8.0.cnf $my_cnf
else
    cp -f "$me_path"/my.5.7.cnf $my_cnf
fi

chmod 0644 $my_cnf

if [ "$MYSQL_SLAVE" = 'true' ]; then
    sed -i \
        -e "/server_id/s/1/${MYSQL_SLAVE_ID:-2}/" \
        -e "/auto_increment_offset/s/1/2/" \
        $my_cnf
fi

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

