#!/usr/bin/bash

# script_path="$(dirname "$(readlink -f "$0")")"
# cd "$script_path" || exit 1
path_install="$HOME/docker/laradock"
file_env="$path_install"/.env

echo "Check dependent: git/docker..."
command -v git || install_git=1
command -v docker || install_docker=1

if [[ $install_git || $install_docker ]]; then
    echo "Check sudo..."
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
fi

[[ $install_git ]] && {
    echo "install git..."
    $cmd install -y git zsh
}
## install docker/compose
[[ $install_docker ]] && {
    echo "install docker..."
    curl -fsSL https://get.docker.com | $pre_sudo bash
}

## set CST
[[ -n "$pre_sudo" || "$current_user" == "root" ]] && $pre_sudo timedatectl set-timezone Asia/Shanghai

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
5.6)
    [ -f "$path_install"/php-fpm/Dockerfile.php71 ] && {
        cp -vf "$path_install"/php-fpm/Dockerfile.php71 "$path_install"/php-fpm/Dockerfile
    }
    sed -i -e "/PHP_VERSION=/s/=.*/=$1/" "$file_env"
    args="php-fpm"
    ;;
7.1)
    [ -f "$path_install"/php-fpm/Dockerfile.php71 ] && {
        cp -vf "$path_install"/php-fpm/Dockerfile.php71 "$path_install"/php-fpm/Dockerfile
    }
    sed -i -e "/PHP_VERSION=/s/=.*/=$1/" "$file_env"
    args="php-fpm"
    ;;
7.4)
    [ -f "$path_install"/php-fpm/Dockerfile.php71 ] && {
        cp -vf "$path_install"/php-fpm/Dockerfile.php71 "$path_install"/php-fpm/Dockerfile
    }
    sed -i -e "/PHP_VERSION=/s/=.*/=$1/" "$file_env"
    args="php-fpm"
    ;;
8.0)
    [ -f "$path_install"/php-fpm/Dockerfile.php80 ] && {
        cp -vf "$path_install"/php-fpm/Dockerfile.php80 "$path_install"/php-fpm/Dockerfile
    }
    sed -i -e "/PHP_VERSION=/s/=.*/=$1/" "$file_env"
    args="php-fpm"
    ;;
gitlab)
    args="gitlab"
    ;;
svn)
    args="usvn"
    ;;
zsh)
    ## install oh my zsh
    bash -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    sed -i -e 's/robbyrussell/ys/' ~/.zshrc
    ;;
*)
    args="nginx"
    ;;
esac

## docker pull ttl.sh
# IMAGE_NAME=$(uuidgen)
# cd "$path_install" && docker-compose build php-fpm
# docker tag laradock_php-fpm ttl.sh/"${IMAGE_NAME}":2h
# docker push ttl.sh/"${IMAGE_NAME}":2h
# docker pull ttl.sh/"${IMAGE_NAME}":2h

echo -e "\n#### exec command: "
if command -v docker-compose &>/dev/null; then
    echo -e "\ncd $path_install && docker-compose up -d $args\n"
else
    echo -e "\ncd $path_install && docker compose up -d $args\n"
fi
