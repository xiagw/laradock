#!/bin/bash

set -xe

sed -i \
    -e '/fpm.sock/s/^/;/' \
    -e '/fpm.sock/a listen = 9000' \
    -e '/rlimit_files/a rlimit_files = 65535' \
    -e '/pm.max_children/s/5/10000/' \
    -e '/pm.start_servers/s/2/10/' \
    -e '/pm.min_spare_servers/s/1/10/' \
    -e '/pm.max_spare_servers/s/3/20/' \
    /etc/php/"${LARADOCK_PHP_VERSION}"/fpm/pool.d/www.conf
sed -i \
    -e "/memory_limit/s/128M/1024M/" \
    -e "/post_max_size/s/8M/1024M/" \
    -e "/upload_max_filesize/s/2M/1024M/" \
    -e "/max_file_uploads/s/20/1024/" \
    -e '/disable_functions/s/$/phpinfo,eval,exec,shell_exec,/' \
    -e '/max_execution_time/s/30/60/' \
    /etc/php/"${LARADOCK_PHP_VERSION}"/fpm/php.ini

if [ "$PHP_SESSION_REDIS" = true ]; then
    sed -i -e "/session.save_handler/s/files/redis/" \
        -e "/session.save_handler/a session.save_path = \"tcp://${PHP_SESSION_REDIS_SERVER}:${PHP_SESSION_REDIS_PORT}?auth=${PHP_SESSION_REDIS_PASS}&database=${PHP_SESSION_REDIS_DB}\"" \
        /etc/php/"${LARADOCK_PHP_VERSION}"/fpm/php.ini
fi

## setup nginx for ThinkPHP
if [ -d /etc/nginx/sites-enabled ]; then
    rm -f /etc/nginx/sites-enabled/default
    cp -vf /opt/nginx.conf /etc/nginx/sites-available/
    ln -sf /etc/nginx/sites-available/nginx.conf /etc/nginx/sites-enabled/default
fi

if [ ! -x /opt/run.sh ]; then
    chmod +x /opt/run.sh
fi
