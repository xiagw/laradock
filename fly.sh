#!/usr/bin/bash

set -e

_msg() {
    color_off='\033[0m' # Text Reset
    case "${1:-none}" in
    red | error | erro) color_on='\033[0;31m' ;;       # Red
    green | info) color_on='\033[0;32m' ;;             # Green
    yellow | warning | warn) color_on='\033[0;33m' ;;  # Yellow
    blue) color_on='\033[0;34m' ;;                     # Blue
    purple | question | ques) color_on='\033[0;35m' ;; # Purple
    cyan) color_on='\033[0;36m' ;;                     # Cyan
    time)
        color_on="[+] $(date +%Y%m%d-%T-%u), "
        color_off=''
        ;;
    stepend)
        color_on="[+] $(date +%Y%m%d-%T-%u), "
        color_off=' ... end'
        ;;
    step | timestep)
        color_on="\033[0;33m[$((${STEP:-0} + 1))] $(date +%Y%m%d-%T-%u), \033[0m"
        STEP=$((${STEP:-0} + 1))
        color_off=' ... start'
        ;;
    *)
        color_on=''
        color_off=''
        need_shift=0
        ;;
    esac
    [ "${need_shift:-1}" -eq 1 ] && shift
    need_shift=1
    echo -e "${color_on}$*${color_off}"
}

_log() {
    _msg time "$*" | tee -a "$me_log"
}

_get_yes_no() {
    if [[ "$1" == timeout ]]; then
        shift
        echo "Automatic answer N within 20 seconds ..."
        read -t 20 -rp "${1:-Confirm the action?} [y/N] " read_yes_no
    else
        read -rp "${1:-Confirm the action?} [y/N] " read_yes_no
    fi
    if [[ ${read_yes_no:-n} =~ ^(y|Y|yes|YES)$ ]]; then
        return 0
    else
        return 1
    fi
}

_check_sudo() {
    _msg step "check sudo."
    # determine whether the user has permission to execute this script
    current_user=$(whoami)
    if [ "$current_user" != "root" ]; then
        _msg time "Not root, check sudo..."
        has_root_permission=$(sudo -l -U "$current_user" | grep "ALL")
        if [ -n "$has_root_permission" ]; then
            _msg time "User $current_user has sudo permission."
            pre_sudo="sudo"
        else
            _msg time "User $current_user has no permission to execute this script!"
            _msg time "Please run visudo with root, and set sudo to $USER"
            return 1
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
        return 1
    fi
}

_check_dependence() {
    _msg step "check command: git/curl/docker..."
    command -v git && echo ok || install_git=1
    command -v curl && echo ok || install_curl=1
    command -v docker && echo ok || install_docker=1
    if [[ $install_git || $install_curl || $install_docker ]]; then
        _check_sudo
    fi
    [[ $install_curl ]] && {
        _msg step "install curl..."
        $cmd install -y curl
    }
    [[ $install_git ]] && {
        _msg step "install git..."
        $cmd install -y git zsh
    }
    ## install docker/compose
    [[ $install_docker ]] && {
        _msg step "install docker..."
        if grep -q '^ID=.alinux' /etc/os-release; then
            sed -i -e '/^ID=/s/alinux/centos/' /etc/os-release
            update_os_release=1
        fi
        curl -fsSL https://get.docker.com | $pre_sudo bash
        if [ "$current_user" != "root" ]; then
            _msg time "Add user $USER to group docker."
            $pre_sudo usermod -aG docker "$USER"
            _msg red "Please logout $USER, and login again."
        fi
        if id ubuntu; then
            $pre_sudo usermod -aG docker ubuntu
        fi
        [[ ${update_os_release:-0} -eq 1 ]] && sed -i -e '/^ID=/s/centos/alinux/' /etc/os-release
        $pre_sudo systemctl start docker
    }
    $pre_sudo chown 1000:1000 "$path_laradock/spring"
    return 0
}

_check_timezone() {
    ## change UTC to CST
    _msg step "check timezone ..."
    if timedatectl | grep -q 'Asia/Shanghai'; then
        _msg time "Timezone is already set to Asia/Shanghai."
    else
        if [[ -n "$pre_sudo" || "$current_user" == "root" ]]; then
            _msg time "Set timezone to Asia/Shanghai."
            $pre_sudo timedatectl set-timezone Asia/Shanghai
        fi
    fi
}

_check_laradock() {
    ## clone laradock or git pull
    _msg step "git clone laradock ..."
    if [ -d "$path_laradock" ]; then
        _msg time "$path_laradock exist, git pull."
        (cd "$path_laradock" && git pull)
    else
        _msg time "install laradock to $path_laradock."
        mkdir -p "$path_laradock"
        git clone -b in-china --depth 1 https://gitee.com/xiagw/laradock.git "$path_laradock"
    fi
    ## copy .env.example to .env
    _msg step "set laradock .env ..."
    if [ ! -f "$file_env" ]; then
        _msg time "copy .env.example to .env, and set password"
        cp -vf "$file_env".example "$file_env"
        pass_mysql="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
        pass_mysql_default="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
        pass_redis="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
        pass_gitlab="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
        sed -i \
            -e "/^MYSQL_PASSWORD/s/=.*/=$pass_mysql_default/" \
            -e "/MYSQL_ROOT_PASSWORD/s/=.*/=$pass_mysql/" \
            -e "/REDIS_PASSWORD/s/=.*/=$pass_redis/" \
            -e "/GITLAB_ROOT_PASSWORD/s/=.*/=$pass_gitlab/" \
            -e "/PHP_VERSION=/s/=.*/=${ver_php}/" \
            -e "/UBUNTU_VERSION=/s/=.*/=${ubuntu_ver}/" \
            -e "/CHANGE_SOURCE=/s/false/true/" \
            "$file_env"
    fi
    ## change docker host ip
    docker_host_ip=$(/sbin/ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
    sed -i \
        -e "/DOCKER_HOST_IP=/s/=.*/=$docker_host_ip/" \
        -e "/GITLAB_HOST_SSH_IP/s/=.*/=$docker_host_ip/" \
        "$file_env"
    ## set SHELL_OH_MY_ZSH=true
    echo "$SHELL" | grep -q zsh && sed -i -e "/SHELL_OH_MY_ZSH=/s/false/true/" "$file_env" || return 0
}

_get_image() {
    [[ "$args" == "php-fpm" ]] || return 0
    _msg step "download docker image of php-fpm..."
    if [ -f "$path_laradock/php-fpm/Dockerfile.php71" ]; then
        cp -f "$path_laradock/php-fpm/Dockerfile.php71" "$path_laradock"/php-fpm/Dockerfile
    fi
    sed -i -e "/PHP_VERSION=/s/=.*/=$ver_php/" "$file_env"
    ref_url=http://www.flyh6.com/
    file_url="http://cdn.flyh6.com/docker/laradock-php-fpm.${ver_php}.tar.gz"
    file_save=/tmp/laradock-php-fpm.tar.gz
    ## download php image
    curl --referer $ref_url -C - -Lo $file_save "$file_url"
    docker load <$file_save
    docker tag laradock_php-fpm laradock-php-fpm
    docker rmi laradock_php-fpm
}

_set_perm() {
    find "$path_laradock/../app" -type d -exec chmod 755 {} \;
    find "$path_laradock/../app" -type f -exec chmod 644 {} \;
    chown 1000:1000 "$path_laradock/spring"
}

_new_app_php() {
    ## create dir 'app' for  php files
    mkdir "$path_laradock/../app"
    ## create nginx app.conf
    \cp -av "$path_laradock/nginx/sites/app.conf.example" "$path_laradock/nginx/sites/app.conf"
    sed -i -e 's/127\.0\.0\.1/php-fpm/' "$path_laradock/nginx/sites/app.conf"
    cd $path_laradock && $dco exec nginx nginx -s reload
    ## create test.php
    cat >"$path_laradock/../app/test.php" <<EOF
<?php
echo 'This is test page for php';

EOF
}

_new_app_java() {
    ## create nginx app.conf
    \cp -av "$path_laradock/nginx/sites/app.conf.example" "$path_laradock/nginx/sites/app.conf"
    sed -i -e 's/127\.0\.0\.1/spring/' "$path_laradock/nginx/sites/app.conf"
    cd $path_laradock && $dco exec nginx nginx -s reload
    echo "cd $path_laradock && $dco up -d spring"
}

_install_zsh() {
    _msg step "install oh my zsh"
    bash -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    omz theme set ys
    omz plugin enable z extract fzf docker-compose
    # sed -i -e 's/robbyrussell/ys/' ~/.zshrc
    # sed -i -e '/^plugins=.*/s//plugins=\(git z extract docker docker-compose\)/' ~/.zshrc
}

_start_manual() {
    _msg step "manual startup ..."
    echo '#########################################'
    if command -v docker-compose &>/dev/null; then
        _msg info "\n  cd $path_laradock && $dco up -d $args \n"
    else
        _msg info "\n  cd $path_laradock && $dco up -d $args \n"
    fi
    echo '#########################################'
}

_start_auto() {
    if _get_yes_no timeout "Do you want start laradock now? "; then
        _msg step "start redis mysql nginx ..."
    else
        return 0
    fi
    cd $path_laradock && $dco up -d redis mysql nginx $args
    _msg time "Test nginx ..."
    until curl --connect-timeout 3 localhost; do
        sleep 1
        c=$((${c:-0} + 1))
        [[ $c -gt 60 ]] && break
    done
    ## create test.php
    \cp -avf "$path_laradock/php-fpm/test.php" "$path_laradock/../public/test.php"
    source $file_env
    sed -i \
        -e "s/ENV_REDIS_PASSWORD/$REDIS_PASSWORD/" \
        -e "s/ENV_MYSQL_USER/$MYSQL_USER/" \
        -e "s/ENV_MYSQL_PASSWORD/$MYSQL_PASSWORD/" \
        "$path_laradock/../public/test.php"
    if [[ "$args" == "php-fpm" ]]; then
        _msg time "Test PHP Redis MySQL ..."
        sed -i -e 's/127\.0\.0\.1/php-fpm/' "$path_laradock/nginx/sites/default.conf"
        $dco exec nginx nginx -s reload
        curl --connect-timeout 3 localhost/test.php
    fi
}

_get_redis_mysql_info() {
    grep ^REDIS_ $file_env | head -n 3
    grep ^DB_HOST $file_env
    grep ^MYSQL_ $file_env | sed -n '2,5 p'
}

_db_import() {
    echo "import sql from <some.file.sql>"
    echo "<skip>"
}

_usage() {
    echo "
Usage: $0 [parameters ...]

Parameters:
    -h, --help               Show this help message.
    -v, --version            Show version info.
    php-new             create new domain for php
    java                start spring
    info
    logs
    start-php
    stop-php
    start-java
    stop-java
    nginx
    ps
    sql

"
}
main() {
    me_path="$(dirname "$(readlink -f "$0")")"
    me_name="$(basename "$0")"
    me_log="${me_path}/${me_name}.log"

    path_laradock="$HOME/docker/laradock"
    file_env="$path_laradock"/.env
    ## Overview | Docker Documentation https://docs.docker.com/compose/install/
    if command -v docker-compose &>/dev/null; then
        dco=docker-compose
    else
        dco="docker compose"
    fi

    ver_php="${1:-nginx}"
    case ${ver_php} in
    5.6 | 7.1 | 7.4)
        args="php-fpm"
        ubuntu_ver=20.04
        ;;
    8.1 | 8.2)
        args="php-fpm"
        ubuntu_ver=22.04
        ;;
    php-new)
        args="php-fpm"
        _new_app_php
        return
        ;;
    java)
        args="spring"
        ;;
    gitlab)
        args="gitlab"
        ;;
    svn)
        args="usvn"
        ;;
    zsh)
        _install_zsh
        return 0
        ;;
    perm)
        _set_perm
        return
        ;;
    info)
        _get_redis_mysql_info
        return
        ;;
    logs)
        $dco logs -f
        return
        ;;
    start-php)
        $dco start php-fpm
        return
        ;;
    stop-php)
        $dco stop php-fpm
        return
        ;;
    start-java)
        $dco start spring
        return
        ;;
    stop-java)
        $dco stop spring
        return
        ;;
    reload)
        cd $path_laradock && $dco exec nginx nginx -s reload
        return
        ;;
    ps)
        $dco ps
        return
        ;;
    sql)
        _db_import
        return
        ;;
    *)
        args="nginx"
        ;;
    esac

    _check_timezone
    _check_dependence
    _check_laradock
    _get_image

    ## startup
    _start_manual
    _start_auto
}

main "$@"
