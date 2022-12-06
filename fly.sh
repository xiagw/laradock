#!/usr/bin/bash

set -e

_msg() {
    color_off='\033[0m' # Text Reset
    case "$1" in
    red | error | erro) color_on='\033[0;31m' ;;       # Red
    green | info) color_on='\033[0;32m' ;;             # Green
    yellow | warning | warn) color_on='\033[0;33m' ;;  # Yellow
    blue) color_on='\033[0;34m' ;;                     # Blue
    purple | question | ques) color_on='\033[0;35m' ;; # Purple
    cyan) color_on='\033[0;36m' ;;                     # Cyan
    time)
        color_on="[+] $(date +%Y%m%d-%T-%u), " ## datetime
        color_off=''
        ;;
    step | timestep)
        color_on="\033[0;33m[$((${STEP:-0} + 1))] $(date +%Y%m%d-%T-%u), \033[0m"
        STEP=$((${STEP:-0} + 1))
        color_off=''
        ;;
    *)
        color_on=''
        color_off=''
        ;;
    esac
    shift
    echo -e "${color_on}$*${color_off}"
}

_log() {
    _msg time "$*" >>"$me_log"
}

_get_yes_no() {
    read -rp "${1:-Confirm the action?} [y/N] " read_yes_no
    if [[ ${read_yes_no:-n} =~ ^(y|Y|yes|YES)$ ]]; then
        return 0
    else
        return 1
    fi
}

_download_image() {
    ## download php image
    _msg step "download docker image of php-fpm..."
    curl --referer http://www.flyh6.com/ \
        -C - -Lo /tmp/laradock-php-fpm.tar.gz \
        http://cdn.flyh6.com/docker/laradock-php-fpm."${ver_php}".tar.gz
    docker load </tmp/laradock-php-fpm.tar.gz
}

main() {
    me_path="$(dirname "$(readlink -f "$0")")"
    me_name="$(basename "$0")"
    me_log="${me_path}/${me_name}.log"

    path_install="$HOME/docker/laradock"
    file_env="$path_install"/.env
    ##
    _msg step "check command: git/curl/docker..."
    command -v git || install_git=1
    command -v curl || install_curl=1
    command -v docker || install_docker=1
    if [[ $install_git || $install_curl || $install_docker ]]; then
        _msg time "check sudo."
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
            _msg time "not found apt/yum/dnf, exit 1"
            exit 1
        fi
    fi

    [[ $install_curl ]] && {
        _msg time "install curl..."
        $cmd install -y curl
    }
    [[ $install_git ]] && {
        _msg time "install git..."
        $cmd install -y git zsh
    }
    ## install docker/compose
    [[ $install_docker ]] && {
        _msg time "install docker..."
        if grep -q '^ID=.alinux' /etc/os-release; then
            sed -i -e '/^ID=/s/alinux/centos/' /etc/os-release
            update_os_release=1
        fi
        curl -fsSL https://get.docker.com | $pre_sudo bash
        if [ "$current_user" != "root" ]; then
            _msg time "Add user $USER to group docker."
            $pre_sudo usermod -aG docker "$USER"
            _msg time "Please logout $USER, and login again."
        fi
        if id ubuntu; then
            $pre_sudo usermod -aG docker ubuntu
        fi
        [[ ${update_os_release:-0} -eq 1 ]] && sed -i -e '/^ID=/s/centos/alinux/' /etc/os-release
        $pre_sudo systemctl start docker
    }
    ## change UTC to CST
    _msg step "check timedate ..."
    if timedatectl | grep -q 'Asia/Shanghai'; then
        _msg time "Timezone is already set to Asia/Shanghai."
    else
        if [[ -n "$pre_sudo" || "$current_user" == "root" ]]; then
            _msg time "Set timezone to Asia/Shanghai."
            $pre_sudo timedatectl set-timezone Asia/Shanghai
        fi
    fi
    ## clone laradock or git pull
    _msg step "git clone laradock ..."
    if [ -d "$path_install" ]; then
        _msg time "$path_install exist, git pull."
        (cd "$path_install" && git pull)
    else
        _msg time "install laradock to $path_install."
        mkdir -p "$path_install"
        git clone -b in-china --depth 1 https://gitee.com/xiagw/laradock.git "$path_install"
    fi
    ## copy .env.example to .env
    _msg step "laradock .env ..."
    if [ ! -f "$file_env" ]; then
        _msg time "copy .env.example to .env, and update password"
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
    _msg time "change docker host ip."
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

    _msg step "startup ..."
    echo '#########################################'
    if command -v docker-compose &>/dev/null; then
        echo -e "\n  cd $path_install && docker-compose up -d $args \n"
    else
        echo -e "\n  cd $path_install && docker compose up -d $args \n"
    fi
    echo '#########################################'
}

main "$@"
