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
command -v docker || curl -fsSL https://get.docker.com | sudo bash

## clone laradock
[ -d "$path_install" ] || mkdir -p "$path_install"
git clone -b in-china --depth 1 https://gitee.com/xiagw/laradock.git "$path_install"

## cp .env
[ -f "$file_env" ] || cp -vf "$file_env".example "$file_env"

## change docker host ip
docker_host_ip=$(/sbin/ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
sed -i -e "/DOCKER_HOST_IP=/s/=.*/=$docker_host_ip/" \
    -e "/GITLAB_HOST_SSH_IP/s/=.*/=$docker_host_ip/" "$file_env"

## new password for mysql and redis
pass_mysql=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
pass_redis=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
pass_gitlab=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
sed -i -e "/MYSQL_ROOT_PASSWORD/s/=.*/=$pass_mysql/" \
    -e "/REDIS_PASSWORD/s/=.*/=$pass_redis/" \
    -e "/GITLAB_ROOT_PASSWORD/s/=.*/=$pass_gitlab/" "$file_env"

## php 7.1
echo "use php 7.1"
cp -vf "$path_install"/php-fpm/Dockerfile.php71 "$path_install"/php-fpm/Dockerfile

if command -v docker-compose; then
    echo "cd $path_install && docker-compose up -d nginx mysql redis php-fpm"
else
    echo "cd $path_install && docker compose up -d nginx mysql redis php-fpm"
fi
