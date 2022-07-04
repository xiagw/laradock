#!/usr/bin/bash

# script_path="$(dirname "$(readlink -f "$0")")"
# cd "$script_path" || exit 1
path_install="$HOME/docker/laradock"
file_env="$path_install"/.env

# determine whether the user has permission to execute this script
current_user=$(whoami)
if [ "$current_user" != "root" ]; then
    has_root_permission=$(sudo -l -U "$current_user" | grep "ALL")
    if [ -n "$has_root_permission" ]; then
        echo "User $current_user has sudo permission."
        pre_sudo="sudo"
    else
        echo "User $current_user has no permission to execute this script!"
        exit 1
    fi
fi

## yum or apt
if command -v apt; then
    cmd="$pre_sudo apt"
elif command -v yum; then
    cmd="$pre_sudo yum"
elif command -v dnf; then
    cmd="$pre_sudo dnf"
else
    echo "not found apt/yum/dnf, exit 1"
    exit 1
fi

## install git
command -v git || {
    echo "install git..."
    $cmd install -y git
}

## install docker/compose
command -v docker || {
    echo "install docker"
    curl -fsSL https://get.docker.com | $pre_sudo bash
}

## clone laradock
[ -d "$path_install" ] || mkdir -p "$path_install"
git clone -b in-china --depth 1 https://gitee.com/xiagw/laradock.git "$path_install"

## cp .env
if [ ! -f "$file_env" ]; then
    cp -vf "$file_env".example "$file_env"
    ## new password for mysql and redis
    pass_mysql=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
    pass_redis=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
    pass_gitlab=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
    sed -i \
        -e "/MYSQL_ROOT_PASSWORD/s/=.*/=$pass_mysql/" \
        -e "/REDIS_PASSWORD/s/=.*/=$pass_redis/" \
        -e "/GITLAB_ROOT_PASSWORD/s/=.*/=$pass_gitlab/" \
        "$file_env"
fi
## change docker host ip
docker_host_ip=$(/sbin/ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
sed -i \
    -e "/DOCKER_HOST_IP=/s/=.*/=$docker_host_ip/" \
    -e "/GITLAB_HOST_SSH_IP/s/=.*/=$docker_host_ip/" \
    "$file_env"
## set SHELL_OH_MY_ZSH=true
echo "$SHELL" | grep -q zsh && sed -i -e "/SHELL_OH_MY_ZSH=/s/false/true/" "$file_env"

case ${1:-nginx} in
php56)
    [ -f "$path_install"/php-fpm/Dockerfile.php56 ] && {
        cp -vf "$path_install"/php-fpm/Dockerfile.php56 "$path_install"/php-fpm/Dockerfile
    }
    args="php-fpm"
    ;;
php71)
    [ -f "$path_install"/php-fpm/Dockerfile.php71 ] && {
        cp -vf "$path_install"/php-fpm/Dockerfile.php71 "$path_install"/php-fpm/Dockerfile
    }
    args="php-fpm"
    ;;
php74)
    [ -f "$path_install"/php-fpm/Dockerfile.php74 ] && {
        cp -vf "$path_install"/php-fpm/Dockerfile.php74 "$path_install"/php-fpm/Dockerfile
    }
    args="php-fpm"
    ;;
gitlab)
    args="gitlab"
    ;;
svn)
    args="usvn"
    ;;
*)
    args="nginx"
    ;;
esac

echo -e "\n#### exec command: "
if command -v docker-compose &>/dev/null; then
    echo -e "\ncd $path_install && docker-compose up -d $args\n"
else
    echo -e "\ncd $path_install && docker compose up -d $args\n"
fi
