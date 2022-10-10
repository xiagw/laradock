#!/usr/bin/bash

# me_path="$(dirname "$(readlink -f "$0")")"
# cd "$me_path" || exit 1
path_install="$HOME/docker/laradock"
file_env="$path_install"/.env

log_time() {
    echo -e "[$(date +%Y%m%d-%T)], $* \n"
}

log_time "check command: git/curl/docker..."
command -v git || install_git=1
command -v curl || install_curl=1
command -v docker || install_docker=1

if [[ $install_git || $install_curl || $install_docker ]]; then
    log_time "check sudo."
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
## change UTC to CST
if timedatectl | grep -q 'Asia/Shanghai'; then
    log_time "Timezone is already set to Asia/Shanghai."
else
    if [[ -n "$pre_sudo" || "$current_user" == "root" ]]; then
        log_time "Set timezone to Asia/Shanghai."
        $pre_sudo timedatectl set-timezone Asia/Shanghai
    fi
fi
## clone laradock or git pull
if [ -d "$path_install" ]; then
    log_time "$path_install exist, git pull."
    (cd "$path_install" && git pull)
else
    log_time "install laradock to $path_install."
    mkdir -p "$path_install"
    git clone -b in-china --depth 1 https://gitee.com/xiagw/laradock.git "$path_install"
fi
## copy .env.example to .env
if [ ! -f "$file_env" ]; then
    log_time "copy .env.example to .env, and update password"
    cp -vf "$file_env".example "$file_env"
    pass_mysql=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
    pass_redis=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
    pass_gitlab=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
    sed -i \
        -e "/MYSQL_ROOT_PASSWORD/s/=.*/=$pass_mysql/" \
        -e "/REDIS_PASSWORD/s/=.*/=$pass_redis/" \
        -e "/GITLAB_ROOT_PASSWORD/s/=.*/=$pass_gitlab/" \
        -e "/PHP_VERSION=/s/=.*/=7.1/" \
        "$file_env"
fi
## change docker host ip
log_time "change docker host ip."
docker_host_ip=$(/sbin/ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
sed -i \
    -e "/DOCKER_HOST_IP=/s/=.*/=$docker_host_ip/" \
    -e "/GITLAB_HOST_SSH_IP/s/=.*/=$docker_host_ip/" \
    "$file_env"
## set SHELL_OH_MY_ZSH=true
echo "$SHELL" | grep -q zsh && sed -i -e "/SHELL_OH_MY_ZSH=/s/false/true/" "$file_env"

ver_php="${1:-nginx}"
case ${ver_php} in
5.6 | 7.1 | 7.4)
    [ -f "$path_install"/php-fpm/Dockerfile.php71 ] && {
        cp -f "$path_install"/php-fpm/Dockerfile.php71 "$path_install"/php-fpm/Dockerfile
    }
    sed -i -e "/PHP_VERSION=/s/=.*/=$ver_php/" "$file_env"
    args="php-fpm"
    ;;
8.1 | 8.2)
    [ -f "$path_install"/php-fpm/Dockerfile.php81 ] && {
        cp -f "$path_install"/php-fpm/Dockerfile.php81 "$path_install"/php-fpm/Dockerfile
    }
    sed -i -e "/PHP_VERSION=/s/=.*/=$ver_php/" "$file_env"
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
log_time "download docker image of php-fpm."
if [[ "$ver_php" =~ (5.6|7.1|7.4|8.1|8.2) ]]; then
    curl --referer http://www.flyh6.com/ \
        -C - -Lo /tmp/laradock_php-fpm.tar.gz \
        http://cdn.flyh6.com/docker/laradock_php-fpm."${ver_php}".tar.gz
    docker load </tmp/laradock_php-fpm.tar.gz
fi
## docker pull ttl.sh
# IMAGE_NAME="ttl.sh/$(uuidgen):1h"
# docker tag laradock_php-fpm:latest "${IMAGE_NAME}"
# docker push "${IMAGE_NAME}"
# echo "IMAGE_NAME=${IMAGE_NAME}"
#

echo '#########################################'
if command -v docker-compose &>/dev/null; then
    echo -e "\n  cd $path_install && docker-compose up -d $args \n"
else
    echo -e "\n  cd $path_install && docker compose up -d $args \n"
fi
echo '#########################################'
