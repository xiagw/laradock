#!/bin/sh

me_name="$(basename "$0")"
me_path="$(dirname "$(readlink -f "$0")")"
me_log="${me_path}/${me_name}.log"

# groupmod -g 1000 nginx
# usermod -u 1000 nginx

if [ -f $me_path/nginx.conf ]; then
    cp -vf $me_path/nginx.conf /etc/nginx/
fi
if [ -f $me_path/run.sh ]; then
    cp -vf $me_path/run.sh /docker-entrypoint.d/
    sed -i 's/\r//g' /docker-entrypoint.d/run.sh
    chmod +x /docker-entrypoint.d/run.sh
fi
