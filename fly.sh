#!/usr/bin/env bash

_msg() {
    color_off='\033[0m' # Text Reset
    case "${1:-none}" in
    red | error | err) color_on='\033[0;31m' ;;        # Red
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
        color_off=' ... '
        ;;
    step | timestep)
        color_on="\033[0;33m[$((${STEP:-0} + 1))] $(date +%Y%m%d-%T-%u), \033[0m"
        STEP=$((${STEP:-0} + 1))
        color_off=' ... '
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
        echo "Automatic answer 'N' within 20 seconds"
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

_command_exists() {
    command -v "$@" &>/dev/null
}

_get_distribution() {
    if [ -r /etc/os-release ]; then
        lsb_dist="$(. /etc/os-release && echo "$ID")"
        lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
    else
        lsb_dist='unknown'
    fi
}

_check_sudo() {
    [[ "$check_sudo_flag" -eq 1 ]] && return 0
    if [ "$USER" != "root" ]; then
        if sudo -l -U "$USER" | grep -q "ALL"; then
            pre_sudo="sudo"
        else
            echo "User $USER has no permission to execute this script!"
            echo "Please run visudo with root, and set sudo to $USER"
            return 1
        fi
    fi
    if _command_exists apt; then
        cmd="$pre_sudo apt"
    elif _command_exists yum; then
        cmd="$pre_sudo yum"
    elif _command_exists dnf; then
        cmd="$pre_sudo dnf"
    else
        _msg time "not found apt/yum/dnf, exit 1"
        return 1
    fi
    check_sudo_flag=1
}

_check_dependence() {
    _msg step "check command: curl/git/docker"
    _command_exists curl || {
        $cmd install -y curl
    }
    _command_exists git || {
        $cmd install -y git zsh
    }
    ## install docker/compose
    if ! _command_exists docker; then
        if grep -q '^ID=alinux' /etc/os-release; then
            sed -i -e '/^ID=/s/alinux/centos/' /etc/os-release
            update_os_release=1
        fi
        if [[ "${IN_CHINA:-true}" == true ]]; then
            curl -fsSL --connect-timeout 10 https://get.docker.com | $pre_sudo bash -s - --mirror Aliyun
        else
            curl -fsSL --connect-timeout 10 https://get.docker.com | $pre_sudo bash
        fi
        if [[ "$USER" != "root" ]]; then
            _msg time "Add user $USER to group docker."
            $pre_sudo usermod -aG docker "$USER"
            _msg red "Please logout $USER, and login again."
            need_logout=1
        fi
        if [[ "$USER" != ubuntu ]] && id ubuntu; then
            $pre_sudo usermod -aG docker ubuntu
        fi
        if [[ "$USER" != centos ]] && id centos; then
            $pre_sudo usermod -aG docker centos
        fi
        if [[ "$USER" != ops ]] && id ops; then
            $pre_sudo usermod -aG docker ops
        fi
        [[ ${update_os_release:-0} -eq 1 ]] && sed -i -e '/^ID=/s/centos/alinux/' /etc/os-release
        $pre_sudo systemctl start docker
    fi
    _command_exists strings || $cmd install -y binutils
    return 0
}

_check_timezone() {
    ## change UTC to CST
    _msg step "check timezone "
    if timedatectl | grep -q 'Asia/Shanghai'; then
        _msg time "Timezone is already set to Asia/Shanghai."
    else
        _msg time "Set timezone to Asia/Shanghai."
        $pre_sudo timedatectl set-timezone Asia/Shanghai
    fi
}

_check_laradock() {
    if [ -d "$laradock_path" ]; then
        _msg time "$laradock_path exist, git pull."
        (cd "$laradock_path" && git pull)
        return 0
    fi
    ## clone laradock or git pull
    _msg step "install laradock to $laradock_path."
    mkdir -p "$laradock_path"
    if [[ "${IN_CHINA:-true}" == true ]]; then
        git clone -b in-china --depth 1 https://gitee.com/xiagw/laradock.git "$laradock_path"
    else
        git clone -b in-china --depth 1 https://github.com/xiagw/laradock.git "$laradock_path"
    fi
    ## jdk image, uid is 1000.(see spring/Dockerfile)
    $pre_sudo chown 1000:1000 "$laradock_path/spring"
}

_set_laradock_env() {
    if [[ -f "$laradock_env" && "${force_update_env:-0}" -eq 0 ]]; then
        return 0
    fi
    _msg step "set laradock .env"
    pass_mysql="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
    pass_mysql_default="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
    pass_redis="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
    pass_gitlab="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
    ## change docker host ip
    docker_host_ip=$(/sbin/ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)

    _msg time "copy .env.example to .env, and set password"
    cp -vf "$laradock_env".example "$laradock_env"
    sed -i \
        -e "/^MYSQL_PASSWORD/s/=.*/=$pass_mysql_default/" \
        -e "/MYSQL_ROOT_PASSWORD/s/=.*/=$pass_mysql/" \
        -e "/MYSQL_VERSION=latest/s/=.*/=5.7/" \
        -e "/REDIS_PASSWORD/s/=.*/=$pass_redis/" \
        -e "/GITLAB_ROOT_PASSWORD/s/=.*/=$pass_gitlab/" \
        -e "/PHP_VERSION=/s/=.*/=${php_ver}/" \
        -e "/UBUNTU_VERSION=/s/=.*/=${ubuntu_ver}/" \
        -e "/CHANGE_SOURCE=/s/false/true/" \
        -e "/DOCKER_HOST_IP=/s/=.*/=$docker_host_ip/" \
        -e "/GITLAB_HOST_SSH_IP/s/=.*/=$docker_host_ip/" \
        "$laradock_env"
    ## set SHELL_OH_MY_ZSH=true
    echo "$SHELL" | grep -q zsh && sed -i -e "/SHELL_OH_MY_ZSH=/s/false/true/" "$laradock_env" || return 0
}

_restart_nginx() {
    cd $laradock_path && $dco exec nginx nginx -s reload
}

_set_nginx_php() {
    ## setup php upstream
    sed -i -e 's/127\.0\.0\.1/php-fpm/g' "$laradock_path/nginx/sites/d.php.inc"
}

_set_nginx_java() {
    ## setup java upstream
    sed -i -e 's/127\.0\.0\.1/spring/g' "$laradock_path/nginx/sites/d.java.inc"
}

_set_php_ver() {
    sed -i \
        -e "/PHP_VERSION=/s/=.*/=${php_ver}/" \
        -e "/UBUNTU_VERSION=/s/=.*/=${ubuntu_ver}/" \
        -e "/CHANGE_SOURCE=/s/false/true/" \
        "$laradock_env"
}

_get_image() {
    if [[ $args == *spring* ]]; then
        return
    fi
    _msg step "download docker image for $1"
    file_save=/tmp/laradock-${1}.tar.gz
    if [[ $1 == *php-fpm* ]]; then
        _set_php_ver
        file_url="http://cdn.flyh6.com/docker/laradock-${1}.${php_ver}.tar.gz"
    else
        file_url="http://cdn.flyh6.com/docker/laradock-${1}.tar.gz"
    fi
    curl -Lo $file_save "${file_url}"
    docker load <$file_save
    if docker --version | grep -q "version 19"; then
        docker tag laradock-$1 laradock_$1
    fi
}

_set_file_mode() {
    _check_sudo
    cd "$laradock_path"/../
    for d in ./*/; do
        [[ "$d" == *laradock* ]] && continue
        find "$d" | while read -r line; do
            [ -d "$line" ] && $pre_sudo chmod 755 "$line"
            [ -f "$line" ] && $pre_sudo chmod 644 "$line"
            if [[ "$line" == *runtime ]]; then
                $pre_sudo rm -rf "${line:?}"/*
                $pre_sudo chown -R 33:33 "$line"
            fi
            if [[ "$line" == *config/app.php ]]; then
                grep -q 'app_debug.*true' "$line" && $pre_sudo sed -i -e '/app_debug/s/true/false/' "$line"
            fi
            if [[ "$line" == *config/log.php ]]; then
                grep -q "'level'.*\[\]\," "$line" && $pre_sudo sed -i -e "/'level'/s/\[/\['warning'/" "$line"
            fi
        done
    done
    $pre_sudo chown 1000:1000 "$laradock_path/spring"
    cd -
}

_install_zsh() {
    _msg step "install oh my zsh"
    _check_sudo
    $cmd install zsh
    if [[ "${IN_CHINA:-true}" == true ]]; then
        [ -d "$HOME"/.oh-my-zsh ] || git clone https://gitee.com/mirrors/ohmyzsh.git $HOME/.oh-my-zsh
    else
        bash -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    fi
    cp $HOME/.oh-my-zsh/templates/zshrc.zsh-template $HOME/.zshrc
    omz theme set ys
    omz plugin enable z extract fzf docker-compose
    # sed -i -e 's/robbyrussell/ys/' ~/.zshrc
    # sed -i -e '/^plugins=.*/s//plugins=\(git z extract docker docker-compose\)/' ~/.zshrc
}

_start_manual() {
    _msg step "manual startup "
    _msg info '#########################################'
    _msg info "\n cd $laradock_path && $dco up -d nginx redis mysql $args \n"
    _msg info '#########################################'
    _msg red 'startup automatic after sleep 15s' && sleep 15
}

_start_auto() {
    # if ss -lntu4 | grep -E ':80|:443|:6379|:3306'; then
    #     _msg red "ERR: port already start"
    #     _msg "Please fix $laradock_env, manual start docker."
    #     return 1
    # fi
    _msg step "auto startup"
    cd $laradock_path && $dco up -d nginx redis mysql ${args:-php-fpm spring}
}

_test_nginx() {
    _msg time "Test nginx "
    until curl --connect-timeout 3 localhost; do
        sleep 2
        c=$((${c:-0} + 1))
        [[ $c -gt 30 ]] && break
    done
}

_test_php() {
    _check_sudo
    _msg step "create test.php"
    path_nginx_root="$laradock_path/../html"
    $pre_sudo chown $USER:$USER "$path_nginx_root"
    ## create test.php
    $pre_sudo cp -avf "$laradock_path/php-fpm/test.php" "$path_nginx_root/test.php"
    source $laradock_env
    sed -i \
        -e "s/ENV_REDIS_PASSWORD/$REDIS_PASSWORD/" \
        -e "s/ENV_MYSQL_USER/$MYSQL_USER/" \
        -e "s/ENV_MYSQL_PASSWORD/$MYSQL_PASSWORD/" \
        "$path_nginx_root/test.php"
    _msg time "Test PHP Redis MySQL "
    _set_nginx_php
    _restart_nginx
    while [[ "${get_status:-502}" -gt 200 ]]; do
        curl --connect-timeout 3 localhost/test.php
        get_status="$(curl -Lo /dev/null -fsSL -w "%{http_code}" localhost/test.php)"
        echo "http_code: $get_status"
        sleep 2
        c=$((${c:-0} + 1))
        [[ $c -gt 30 ]] && {
            echo "break after 60s"
            break
        }
    done
}

_test_java() {
    _msg "Test spring."
}

_get_redis_mysql_info() {
    grep ^REDIS_ $laradock_env | head -n 3
    grep ^DB_HOST $laradock_env
    grep ^MYSQL_ $laradock_env | sed -n '2,5 p'
}

_mysql_cli() {
    echo "exec mysql"
    password_default=$(awk -F= '/^MYSQL_PASSWORD/ {print $2}' "$laradock_env")
    $dco exec mysql bash -c "LANG=C.UTF-8 mysql default -u default -p$password_default"
}

_install_lsyncd() {
    _msg "install lsyncd"
    _check_sudo
    _command_exists lsyncd || $cmd install -y lsyncd
    _msg "new lsyncd.conf.lua"
    lsyncd_conf=/etc/lsyncd/lsyncd.conf.lua
    [ -d /etc/lsyncd/ ] || $pre_sudo mkdir /etc/lsyncd
    $pre_sudo cp "$laradock_path"/usvn$lsyncd_conf $lsyncd_conf
    [[ "$USER" == "root" ]] || sed -i "s@/root/docker@$HOME/docker@" $lsyncd_conf
    _msg "new key, ssh-keygen"
    [ -f "$HOME/.ssh/id_ed25519" ] || ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N ''
    while read -rp "Enter ssh host IP [${count:=1}] (enter q break): " ssh_host_ip; do
        [[ -z "$ssh_host_ip" || "$ssh_host_ip" == q ]] && break
        _msg "ssh-copy-id root@$ssh_host_ip"
        ssh-copy-id "root@$ssh_host_ip"
        _msg "update $lsyncd_conf"
        line_num=$(grep -n '^targets' $lsyncd_conf | awk -F: '{print $1}')
        $pre_sudo sed -i -e "$line_num a '$ssh_host_ip:$HOME/docker/html/'," $lsyncd_conf
        count=$((count + 1))
    done
}

_upgrade_java() {
    cd $laradock_path
    curl -Lo spring.tar.gz http://cdn.flyh6.com/docker/srping.tar.gz
    tar zxf spring.tar.gz
    $dco stop ${args}
    $dco rm -f
    $dco up -d ${args}
}

_upgrade_php() {
    cd $laradock_path/../html
    curl -Lo tp.tar.gz http://cdn.flyh6.com/docker/tp.tar.gz
    tar zxf tp.tar.gz
}

_usage() {
    echo "
Usage: $0 [parameters ...]

Parameters:
    -h, --help          Show this help message.
    -v, --version       Show version info.
    info                get mysql redis info
    php                 install php-fpm 7.1
    java                install jdk / spring
    mysql               exec into mysql cli
    perm                set file permission
    lsync               setup lsyncd
"
}

_set_args() {
    if [ -z "$1" ]; then
        args="php-fpm spring"
        php_ver="${2:-7.1}"
        return
    fi

    while [ "$#" -gt 0 ]; do
        case "${1}" in
        php)
            args="php-fpm ${args:+${args}}"
            php_ver="${2:-7.1}"
            ubuntu_ver=20.04
            if [[ "$2" =~ (8.0|8.1) ]]; then
                ubuntu_ver=22.04
            fi
            exec_set_php_ver=1
            exec_set_file_mode=1
            exec_set_nginx_php=1
            shift
            ;;
        java | spring)
            args="spring ${args:+${args}}"
            exec_set_file_mode=1
            exec_set_nginx_java=1
            ;;
        upgrade)
            [[ $args == *php-fpm* ]] && exec_upgrade_php=1
            [[ $args == *spring* ]] && exec_upgrade_java=1
            enable_check=0
            ;;
        github)
            IN_CHINA=false
            shift
            ;;
        gitlab)
            args="gitlab"
            ;;
        svn)
            args="usvn"
            ;;
        zsh)
            exec_install_zsh=1
            enable_check=0
            ;;
        perm)
            exec_set_file_mode=1
            enable_check=0
            ;;
        info)
            exec_get_redis_mysql_info=1
            enable_check=0
            ;;
        mysql)
            exec_mysql_cli=1
            enable_check=0
            ;;
        lsync)
            exec_install_lsyncd=1
            enable_check=0
            ;;
        test)
            exec_test=1
            enable_check=0
            ;;
        *)
            _usage
            # return
            ;;
        esac
        shift
    done
}

main() {
    _set_args "$@"
    set -e
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="${me_path}/${me_name}.log"
    if [[ $me_name == 'fly.sh' ]]; then
        ## 从本机当前目录执行 fly.sh
        laradock_path="${me_path:-$HOME}"
    else
        ## 从远程执行 fly.sh , curl "remote_url" | bash -s args
        laradock_path="${me_path:-$HOME}"/docker/laradock
    fi

    laradock_env="$laradock_path"/.env

    ## Overview | Docker Documentation https://docs.docker.com/compose/install/
    # curl -SL https://github.com/docker/compose/releases/download/v2.16.0/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
    if _command_exists docker-compose; then
        dco="docker-compose"
    else
        dco="docker compose"
    fi

    if [[ "${exec_install_zsh:-0}" -eq 1 ]]; then
        _install_zsh
        return
    fi
    if [[ "${exec_install_lsyncd:-0}" -eq 1 ]]; then
        _install_lsyncd
        return
    fi
    if [[ $exec_upgrade_java -eq 1 ]]; then
        _upgrade_java
        return
    fi
    if [[ $exec_upgrade_php -eq 1 ]]; then
        _upgrade_php
        return
    fi
    if [[ "${enable_check:-1}" -eq 1 ]]; then
        _check_sudo
        _check_timezone
        _check_dependence
        _check_laradock
        _set_laradock_env
    fi
    if [[ "$need_logout" -eq 1 ]]; then
        return
    fi
    [[ "${exec_set_nginx_php:-0}" -eq 1 ]] && _set_nginx_php
    [[ "${exec_set_nginx_java:-0}" -eq 1 ]] && _set_nginx_java

    if [[ $args == *php-fpm* ]]; then
        _get_image $args
        _start_manual
        _start_auto
        _test_nginx
        _restart_nginx
        exec_test=1
    fi

    [[ "${exec_set_file_mode:-0}" -eq 1 ]] && _set_file_mode
    [[ "${exec_get_redis_mysql_info:-0}" -eq 1 ]] && _get_redis_mysql_info
    [[ "${exec_mysql_cli:-0}" -eq 1 ]] && _mysql_cli
    [[ "${exec_set_php_ver:-0}" -eq 1 ]] && _set_php_ver
    if [[ "${exec_test:-0}" -eq 1 ]]; then
        _test_php
        _test_java
    fi
}

main "$@"
