#!/usr/bin/bash

# me_path="$(dirname "$(readlink -f "$0")")"
# cd "$me_path" || exit 1
path_install="$HOME/docker/laradock"
file_env="$path_install"/.env

_msg_time() {
    echo -e "[$(date +%Y%m%d-%T)], $* \n"
}

_msg_time "check command: git/curl/docker..."
command -v git || install_git=1
command -v curl || install_curl=1
command -v docker || install_docker=1

if [[ $install_git || $install_curl || $install_docker ]]; then
    _msg_time "check sudo."
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
        _msg_time "not found apt/yum/dnf, exit 1"
        exit 1
    fi
fi

[[ $install_curl ]] && {
    _msg_time "install curl..."
    $cmd install -y curl
}
[[ $install_git ]] && {
    _msg_time "install git..."
    $cmd install -y git zsh
}
## install docker/compose
[[ $install_docker ]] && {
    _msg_time "install docker..."
    if grep -q '^ID=.alinux' /etc/os-release; then
        sed -i -e '/^ID=/s/alinux/centos/' /etc/os-release
        update_os_release=1
    fi
    curl -fsSL https://get.docker.com | $pre_sudo bash
    if [ "$current_user" != "root" ]; then
        echo "Add user $USER to group docker."
        $pre_sudo usermod -aG docker "$USER"
        echo "Please logout $USER, and login again."
    fi
    [[ ${update_os_release:-0} -eq 1 ]] && sed -i -e '/^ID=/s/centos/alinux/' /etc/os-release
}
## change UTC to CST
if timedatectl | grep -q 'Asia/Shanghai'; then
    _msg_time "Timezone is already set to Asia/Shanghai."
else
    if [[ -n "$pre_sudo" || "$current_user" == "root" ]]; then
        _msg_time "Set timezone to Asia/Shanghai."
        $pre_sudo timedatectl set-timezone Asia/Shanghai
    fi
fi
## clone laradock or git pull
if [ -d "$path_install" ]; then
    _msg_time "$path_install exist, git pull."
    (cd "$path_install" && git pull)
else
    _msg_time "install laradock to $path_install."
    mkdir -p "$path_install"
    git clone -b in-china --depth 1 https://gitee.com/xiagw/laradock.git "$path_install"
fi
## copy .env.example to .env
if [ ! -f "$file_env" ]; then
    _msg_time "copy .env.example to .env, and update password"
    cp -vf "$file_env".example "$file_env"
    pass_mysql=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
    pass_redis=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
    pass_gitlab=$(echo "$RANDOM$(date)$RANDOM" | md5sum | base64 | cut -c 1-14)
    sed -i \
        -e "/MYSQL_ROOT_PASSWORD/s/=.*/=$pass_mysql/" \
        -e "/REDIS_PASSWORD/s/=.*/=$pass_redis/" \
        -e "/GITLAB_ROOT_PASSWORD/s/=.*/=$pass_gitlab/" \
        -e "/PHP_VERSION=/s/=.*/=7.1/" \
        -e "/CHANGE_SOURCE=/s/false/true/" \
        "$file_env"
fi
## change docker host ip
_msg_time "change docker host ip."
docker_host_ip=$(/sbin/ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
sed -i \
    -e "/DOCKER_HOST_IP=/s/=.*/=$docker_host_ip/" \
    -e "/GITLAB_HOST_SSH_IP/s/=.*/=$docker_host_ip/" \
    "$file_env"
## set SHELL_OH_MY_ZSH=true
echo "$SHELL" | grep -q zsh && sed -i -e "/SHELL_OH_MY_ZSH=/s/false/true/" "$file_env"

_download_image() {
    ## download php image
    _msg_time "download docker image of php-fpm."
    curl --referer http://www.flyh6.com/ \
        -C - -Lo /tmp/laradock-php-fpm.tar.gz \
        http://cdn.flyh6.com/docker/laradock-php-fpm."${ver_php}".tar.gz
    docker load </tmp/laradock-php-fpm.tar.gz
    ## docker pull ttl.sh
    # IMAGE_NAME="ttl.sh/$(uuidgen):1h"
    # docker tag laradock-php-fpm:latest "${IMAGE_NAME}"
    # docker push "${IMAGE_NAME}"
    # echo "IMAGE_NAME=${IMAGE_NAME}"
    #
}

ver_php="${1:-nginx}"
case ${ver_php} in
5.6 | 7.1 | 7.4)
    [ -f "$path_install"/php-fpm/Dockerfile.php71 ] && {
        cp -f "$path_install"/php-fpm/Dockerfile.php71 "$path_install"/php-fpm/Dockerfile
    }
    sed -i -e "/PHP_VERSION=/s/=.*/=$ver_php/" "$file_env"
    args="php-fpm"
    _download_image
    ;;
8.1 | 8.2)
    [ -f "$path_install"/php-fpm/Dockerfile.php81 ] && {
        cp -f "$path_install"/php-fpm/Dockerfile.php81 "$path_install"/php-fpm/Dockerfile
    }
    sed -i -e "/PHP_VERSION=/s/=.*/=$ver_php/" "$file_env"
    args="php-fpm"
    _download_image
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

echo
echo '#########################################'
if command -v docker-compose &>/dev/null; then
    echo -e "\n  cd $path_install && docker-compose up -d $args \n"
else
    echo -e "\n  cd $path_install && docker compose up -d $args \n"
fi
echo '#########################################'
