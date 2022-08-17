#!/usr/bin/bash

# script_path="$(dirname "$(readlink -f "$0")")"
# cd "$script_path" || exit 1
path_install="$HOME/docker/laradock"
file_env="$path_install"/.env

log_time() {
    echo -e "[$(date +%Y%m%d-%T)], $*"
}

log_time "Check dependent command: git/curl/docker..."
command -v git || install_git=1
command -v curl || install_curl=1
command -v docker || install_docker=1

if [[ $install_git || $install_docker ]]; then
    # determine whether the user has permission to execute this script
    current_user=$(whoami)
    if [ "$current_user" != "root" ]; then
        echo "Not root, check sudo..."
        has_root_permission=$(sudo -l -U "$current_user" | grep "ALL")
        if [ -n "$has_root_permission" ]; then
            echo "User $current_user has sudo permission."
            pre_sudo="sudo"
        else
            echo "User $current_user has no permission to execute this script!"
            echo "Please run visudo with root, and set sudo to $USER"
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
        log_time "not found apt/yum/dnf, exit 1"
        exit 1
    fi
fi

[[ $install_curl ]] && {
    log_time "install curl..."
    $cmd install -y curl
}
[[ $install_git ]] && {
    log_time "install git..."
    $cmd install -y git zsh
}
## install docker/compose
[[ $install_docker ]] && {
    log_time "install docker..."
    curl -fsSL https://get.docker.com | $pre_sudo bash
    if [ "$current_user" != "root" ]; then
        echo "Add user $USER to group docker."
        $pre_sudo usermod -aG docker "$USER"
        echo "Please logout $USER, and login again."
    fi
}
## set CST
if timedatectl | grep -q 'Asia/Shanghai'; then
    log_time "Timezone is already set to Asia/Shanghai."
else
    log_time "Set timezone to Asia/Shanghai."
    if [[ -n "$pre_sudo" || "$current_user" == "root" ]]; then
        $pre_sudo timedatectl set-timezone Asia/Shanghai
    fi
fi

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
8.1)
    [ -f "$path_install"/php-fpm/Dockerfile.php81 ] && {
        cp -vf "$path_install"/php-fpm/Dockerfile.php81 "$path_install"/php-fpm/Dockerfile
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

## download php image
if [[ $1 =~ (5.6|7.1|7.4|8.0) ]]; then
    curl --referer http://www.flyh6.com/ \
        -C - -Lo /tmp/laradock_php-fpm.tar.gz \
        http://cdn.flyh6.com/docker/laradock_php-fpm.${1}.tar.gz
    docker load </tmp/laradock_php-fpm.tar.gz
fi
## docker pull ttl.sh
# IMAGE_NAME=$(uuidgen)
# cd "$path_install" && docker-compose build php-fpm
# docker tag laradock_php-fpm ttl.sh/"${IMAGE_NAME}":2h
# docker push ttl.sh/"${IMAGE_NAME}":2h
# docker pull ttl.sh/"${IMAGE_NAME}":2h

log_time "\n#### exec command: "
if command -v docker-compose &>/dev/null; then
    echo -e "\n  cd $path_install && docker-compose up -d $args\n"
else
    echo -e "\n  cd $path_install && docker compose up -d $args\n"
fi
