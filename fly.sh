#!/usr/bin/bash

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

_check_sudo() {
    if [ "$USER" != "root" ]; then
        _msg step "Not root, check sudo"
        has_root_permission=$(sudo -l -U "$USER" | grep "ALL")
        if [ -n "$has_root_permission" ]; then
            _msg time "User $USER has sudo permission."
            pre_sudo="sudo"
        else
            _msg time "User $USER has no permission to execute this script!"
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
    _msg step "check command: git/curl/docker"
    command -v git && echo ok || install_git=1
    command -v curl && echo ok || install_curl=1
    command -v docker && echo ok || install_docker=1
    _check_sudo
    [[ $install_curl ]] && {
        _msg step "install curl"
        $cmd install -y curl
    }
    [[ $install_git ]] && {
        _msg step "install git"
        $cmd install -y git zsh
    }
    ## install docker/compose
    [[ $install_docker ]] && {
        _msg step "install docker"
        if grep -q '^ID=alinux' /etc/os-release; then
            sed -i -e '/^ID=/s/alinux/centos/' /etc/os-release
            update_os_release=1
        fi
        curl -fsSL --connect-timeout 10 https://get.docker.com | $pre_sudo bash
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
        [[ ${update_os_release:-0} -eq 1 ]] && sed -i -e '/^ID=/s/centos/alinux/' /etc/os-release
        $pre_sudo systemctl start docker
    }
    command -v strings || $cmd install -y binutils
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
    if [ -d "$path_laradock" ]; then
        _msg time "$path_laradock exist, git pull."
        (cd "$path_laradock" && git pull)
        return 0
    fi
    ## clone laradock or git pull
    _msg step "install laradock to $path_laradock."
    mkdir -p "$path_laradock"
    git clone -b in-china --depth 1 https://gitee.com/xiagw/laradock.git "$path_laradock"
    ## jdk image, uid is 1000.(see spring/Dockerfile)
    $pre_sudo chown 1000:1000 "$path_laradock/spring"
}

_set_laradock_env() {
    if [[ -f "$file_env" && "${force_update_env:-0}" -eq 0 ]]; then
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
    cp -vf "$file_env".example "$file_env"
    sed -i \
        -e "/^MYSQL_PASSWORD/s/=.*/=$pass_mysql_default/" \
        -e "/MYSQL_ROOT_PASSWORD/s/=.*/=$pass_mysql/" \
        -e "/REDIS_PASSWORD/s/=.*/=$pass_redis/" \
        -e "/GITLAB_ROOT_PASSWORD/s/=.*/=$pass_gitlab/" \
        -e "/PHP_VERSION=/s/=.*/=${php_ver:-7.1}/" \
        -e "/UBUNTU_VERSION=/s/=.*/=${ubuntu_ver}/" \
        -e "/CHANGE_SOURCE=/s/false/true/" \
        -e "/DOCKER_HOST_IP=/s/=.*/=$docker_host_ip/" \
        -e "/GITLAB_HOST_SSH_IP/s/=.*/=$docker_host_ip/" \
        "$file_env"
    ## set SHELL_OH_MY_ZSH=true
    echo "$SHELL" | grep -q zsh && sed -i -e "/SHELL_OH_MY_ZSH=/s/false/true/" "$file_env" || return 0
}

_reload_nginx() {
    cd $path_laradock && $dco exec nginx nginx -s reload
}

_set_nginx_php() {
    ## setup php upstream
    sed -i -e 's/127\.0\.0\.1/php-fpm/g' "$path_laradock/nginx/sites/d.php.include"
}

_set_nginx_java() {
    ## setup java upstream
    sed -i -e 's/127\.0\.0\.1/spring/g' "$path_laradock/nginx/sites/d.java.include"
}

_set_php_ver() {
    sed -i \
        -e "/PHP_VERSION=/s/=.*/=${php_ver:-7.1}/" \
        -e "/UBUNTU_VERSION=/s/=.*/=${ubuntu_ver}/" \
        -e "/CHANGE_SOURCE=/s/false/true/" \
        "$file_env"
}

_get_php_image() {
    docker images | grep laradock-php-fpm && return 0
    _msg step "download docker image of php-fpm"
    # if [ -f "$path_laradock/php-fpm/Dockerfile.php71" ]; then
    #     cp -f "$path_laradock/php-fpm/Dockerfile.php71" "$path_laradock"/php-fpm/Dockerfile
    # fi
    _set_php_ver
    ref_url=http://www.flyh6.com/
    file_url="http://cdn.flyh6.com/docker/laradock-php-fpm.${php_ver:-7.1}.tar.gz"
    file_save=/tmp/laradock-php-fpm.tar.gz
    ## download php image
    curl --referer $ref_url -Lo $file_save "$file_url"
    docker load <$file_save
    docker tag laradock_php-fpm laradock-php-fpm
    docker rmi laradock_php-fpm
}

_set_file_perm() {
    _check_sudo
    cd "$path_laradock"/../
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
    $pre_sudo chown 1000:1000 "$path_laradock/spring"
    cd -
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
    _msg step "manual startup "
    _msg info '#########################################'
    _msg info "\n cd $path_laradock && $dco up -d nginx redis mysql $args \n"
    _msg info '#########################################'
}

_start_auto() {
    # if ss -lntu4 | grep -E ':80|:443|:6379|:3306'; then
    #     _msg red "ERR: port already start"
    #     _msg "Please fix $file_env, manual start docker."
    #     return 1
    # fi
    _msg step "auto startup"
    cd $path_laradock && $dco up -d nginx redis mysql ${args:-php-fpm spring}
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
    ## create test.php
    path_nginx_root="$path_laradock/../html"
    $pre_sudo chown $USER:$USER "$path_nginx_root"
    $pre_sudo cp -avf "$path_laradock/php-fpm/test.php" "$path_nginx_root/test.php"
    source $file_env
    sed -i \
        -e "s/ENV_REDIS_PASSWORD/$REDIS_PASSWORD/" \
        -e "s/ENV_MYSQL_USER/$MYSQL_USER/" \
        -e "s/ENV_MYSQL_PASSWORD/$MYSQL_PASSWORD/" \
        "$path_nginx_root/test.php"
    _msg time "Test PHP Redis MySQL "
    _set_nginx_php
    _reload_nginx
    while [[ "${get_status:-502}" -gt 200 ]]; do
        curl --connect-timeout 3 localhost/test.php
        get_status="$(curl -Lo /dev/null -fsSL -w "%{http_code}" localhost/test.php)"
        sleep 2
        c=$((${c:-0} + 1))
        [[ $c -gt 30 ]] && break
    done
}

_test_java() {
    _msg "Test spring."
}

_get_redis_mysql_info() {
    grep ^REDIS_ $file_env | head -n 3
    grep ^DB_HOST $file_env
    grep ^MYSQL_ $file_env | sed -n '2,5 p'
}

_mysql_cmd() {
    echo "exec mysql"
    password_default=$(awk -F= '/^MYSQL_PASSWORD/ {print $2}' "$file_env")
    $dco exec mysql bash -c "LANG=C.UTF-8 mysql default -u default -p$password_default"
}

_setup_lsyncd() {
    _msg "install lsyncd"
    _check_sudo
    command -v lsyncd &>/dev/null || $cmd install -y lsyncd
    _msg "new lsyncd.conf.lua"
    lsyncd_conf=/etc/lsyncd/lsyncd.conf.lua
    [ -d /etc/lsyncd/ ] || $pre_sudo mkdir /etc/lsyncd/
    $pre_sudo cp "$path_laradock"/usvn$lsyncd_conf $lsyncd_conf
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

main() {
    set -e
    me_path="$(dirname "$(readlink -f "$0")")"
    me_name="$(basename "$0")"
    me_log="${me_path}/${me_name}.log"

    path_laradock="$HOME/docker/laradock"
    file_env="$path_laradock"/.env

    case "${1:-all}" in
    all)
        args="php-fpm spring"
        ;;
    php | 5.6 | 7.1 | 7.4)
        args="php-fpm"
        if [[ "$1" == 'php' ]]; then
            php_ver="7.1"
        else
            php_ver="${1}"
        fi
        ubuntu_ver=20.04
        exec_set_php_ver=1
        exec_set_file_perm=1
        exec_set_nginx_php=1
        ;;
    8.1 | 8.2)
        args="php-fpm"
        php_ver="${1}"
        ubuntu_ver=22.04
        exec_set_php_ver=1
        exec_set_file_perm=1
        exec_set_nginx_php=1
        ;;
    java)
        args="spring"
        exec_set_file_perm=1
        exec_set_nginx_java=1
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
        exec_set_file_perm=1
        enable_check=0
        ;;
    info)
        exec_get_redis_mysql_info=1
        enable_check=0
        ;;
    mysql)
        exec_mysql_cmd=1
        enable_check=0
        ;;
    lsync)
        exec_setup_lsyncd=1
        enable_check=0
        ;;
    *)
        _usage
        return
        ;;
    esac

    ## Overview | Docker Documentation https://docs.docker.com/compose/install/
    if command -v docker-compose &>/dev/null; then
        dco="docker-compose"
    else
        dco="docker compose"
    fi
    if [[ "${enable_check:-1}" -eq 1 ]]; then
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
        _get_php_image
        _start_manual
        _start_auto
        _test_nginx
        _reload_nginx
        _test_php
    fi
    if [[ $args == *spring* ]]; then
        _start_manual
        _start_auto
        _test_nginx
        _reload_nginx
        _test_java
    fi
    [[ "${exec_install_zsh:-0}" -eq 1 ]] && _install_zsh
    [[ "${exec_set_file_perm:-0}" -eq 1 ]] && _set_file_perm
    [[ "${exec_get_redis_mysql_info:-0}" -eq 1 ]] && _get_redis_mysql_info
    [[ "${exec_mysql_cmd:-0}" -eq 1 ]] && _mysql_cmd
    [[ "${exec_set_php_ver:-0}" -eq 1 ]] && _set_php_ver
    [[ "${exec_setup_lsyncd:-0}" -eq 1 ]] && _setup_lsyncd
}

main "$@"
