#!/usr/bin/env bash

# set -xe
# script_path="$(dirname "$(readlink -f "$0")")"
# cd "$script_path" || exit 1
path_install="$HOME/docker/laradock"
file_env="$path_install"/.env

# determine whether the user has permission to execute this script
prefix=""
current_user=$(whoami)
if [ "$current_user" != "root" ]; then
    has_root_permission=$(sudo -l -U "$current_user" | grep "ALL")
    if [ -n "$has_root_permission" ]; then
        echo "User $current_user has sudo permission"
        prefix="sudo"
    else
        echo "User $current_user has no permission to execute this script!"
        exit 1
    fi
fi

## yum or apt
if command -v apt; then
    cmd="$prefix apt"
elif command -v yum; then
    cmd="$prefix yum"
else
    echo "not found apt/yum, exit 1"
    exit 1
fi

## install git
echo "install git..."
command -v git || $cmd install -y git

## install docker/compose
echo "install docker"
curl -fsSL https://get.docker.com | sudo bash

## clone laradock
[ -d "$path_install" ] || mkdir -p "$path_install"
git clone -b in-china --depth 1 https://gitee.com/xiagw/laradock.git "$path_install"

## cp .env
[ -f "$file_env" ] || cp -vf "$file_env".example "$file_env"

## change docker host ip
docker_host_ip=$(/sbin/ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
sed -i -e "/DOCKER_HOST_IP=/s/=.*/=$docker_host_ip/" "$file_env"
## new password for mysql and redis
pass_mysql=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
pass_redis=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
sed -i -e "/MYSQL_ROOT_PASSWORD/s/=.*/=$pass_mysql/" -e "/REDIS_PASSWORD/s/=.*/=$pass_redis/" "$file_env"

## php 7.1
echo "use php 7.1"
cp -vf "$path_install"/php-fpm/Dockerfile.php71 "$path_install"/php-fpm/Dockerfile

if command -v docker-compose; then
    echo "cd $path_install && docker-compose up -d nginx mysql redis php-fpm"
else
    echo "cd $path_install && docker compose up -d nginx mysql redis php-fpm"
fi

# case $docker_host_ip in
# '192.168.3.22') ## git
#     sed -i -e "/GITLAB_DOMAIN_NAME_GIT=/s/=.*/=git.fly.com/" \
#         -e "/GITLAB_DOMAIN_NAME=/s/=.*/=https:\/\/git.fly.com/" \
#         -e "/GITLAB_CI_SERVER_URL=/s/=.*/=https:\/\/git.fly.com/" \
#         -e "/SONARQUBE_HOSTNAME=/s/=.*/=sonar.fly.com/" \
#         -e "/NEXUS_DOMAIN=/s/=.*/=nexus.fly.com/" \
#         .env
#     ;;
# '192.168.3.24') ## dev www1
#     sed -i \
#         -e "/NGINX_HOST_HTTP_PORT=/s/=.*/=82/" \
#         -e "/NGINX_HOST_HTTPS_PORT=/s/=.*/=445/" \
#         -e "/APISIX_HOST_HTTP_PORT=/s/=.*/=80/" \
#         -e "/APISIX_HOST_HTTPS_PORT=/s/=.*/=443/" \
#         -e "/DOCKER_HOST_IP_DB=/s/=.*/=192.168.3.24/" \
#         .env
#     ;;
# *)
#     echo "Usage: $0"
#     ;;
# esac
