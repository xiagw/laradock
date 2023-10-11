#!/usr/bin/env bash

_msg() {
    local color_on
    local color_off='\033[0m' # Text Reset
    duration=$SECONDS
    h_m_s="$((duration / 3600))h$(((duration / 60) % 60))m$((duration % 60))s"
    time_now="$(date +%Y%m%d-%u-%T.%3N)"

    case "${1:-none}" in
    red | error | erro) color_on='\033[0;31m' ;;       # Red
    green | info) color_on='\033[0;32m' ;;             # Green
    yellow | warning | warn) color_on='\033[0;33m' ;;  # Yellow
    blue) color_on='\033[0;34m' ;;                     # Blue
    purple | question | ques) color_on='\033[0;35m' ;; # Purple
    cyan) color_on='\033[0;36m' ;;                     # Cyan
    orange) color_on='\033[1;33m' ;;                   # Orange
    step)
        ((++STEP))
        color_on="\033[0;36m[${STEP}] $time_now \033[0m"
        color_off=" $h_m_s"
        ;;
    time)
        color_on="[${STEP}] $time_now "
        color_off=" $h_m_s"
        ;;
    log)
        shift
        echo "$time_now $*" >>$me_log
        return
        ;;
    *)
        unset color_on color_off
        ;;
    esac
    [ "$#" -gt 1 ] && shift
    echo -e "${color_on}$*${color_off}"
}

_get_yes_no() {
    if [[ "$1" == timeout ]]; then
        shift
        _msg time "Automatic answer 'N' within 20 seconds"
        read -t 20 -rp "${1:-Confirm the action?} [y/N] " read_yes_no
    else
        read -rp "${1:-Confirm the action?} [y/N] " read_yes_no
    fi
    case ${read_yes_no:-n} in
    [Nn] | [Nn][Oo])
        return 1
        ;;
    [Yy] | [Yy][Ee][Ss])
        return 0
        ;;
    esac
}

_command_exists() {
    for c in "$@"; do
        command -v "$c"
    done
}

_get_distribution() {
    if [ -r /etc/os-release ]; then
        lsb_dist="$(. /etc/os-release && echo "$ID")"
        lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
    else
        lsb_dist='unknown'
    fi
}

_is_root() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

_check_sudo() {
    ${already_check_sudo:-false} && return 0
    if _is_root; then
        unset pre_sudo
    else
        if sudo -l -U "$USER"; then
            pre_sudo="sudo"
        else
            _msg time "User $USER has no permission to execute this script!"
            _msg time "Please run visudo with root, and set sudo to $USER"
            return 1
        fi
    fi
    if _command_exists apt; then
        cmd="$pre_sudo apt"
        apt_update=1
    elif _command_exists yum; then
        cmd="$pre_sudo yum"
    elif _command_exists dnf; then
        cmd="$pre_sudo dnf"
    else
        _msg time "not found apt/yum/dnf, exit 1"
        return 1
    fi
    already_check_sudo=true
}

_check_dependence() {
    _msg step "check command: curl/git/zsh/binutils"
    for key in $(
        curl -fsSL 'https://api.github.com/users/xiagw/keys' |
            awk -F: '/key/ {gsub(/[" ]/,""); print $2}'
    ); do
        if grep "$key" "$HOME"/.ssh/authorized_keys; then
            _msg time "key $key already exists in authorized_keys"
        else
            _msg time "add key $key to authorized_keys"
            echo "$key" >>"$HOME"/.ssh/authorized_keys
        fi
    done

    pkgs=()
    _command_exists curl || pkgs+=(curl)
    _command_exists git || pkgs+=(git)
    _command_exists zsh || pkgs+=(zsh)
    _command_exists strings || pkgs+=(binutils)
    if [[ "${#pkgs[@]}" -gt 0 ]]; then
        [[ "${apt_update:-0}" -eq 1 ]] && $cmd update -yqq
        $cmd install -yq "${pkgs[@]}"
    fi
    if ${set_sysctl:-false}; then
        grep '^vm.overcommit_memory' /etc/sysctl.conf ||
            echo 'vm.overcommit_memory = 1' | $pre_sudo tee -a /etc/sysctl.conf
    else
        :
    fi
}

_check_docker() {
    _msg step "check docker"
    if _command_exists docker; then
        _msg time "docker is already installed."
        return
    fi

    ## aliyun linux fake centos
    if grep -q '^ID=.*alinux.*' /etc/os-release; then
        $pre_sudo sed -i -e '/^ID=/s/alinux/centos/' /etc/os-release
        aliyun_os=true
    fi
    get_docker=https://cdn.flyh6.com/docker/get-docker.sh
    if ${aliyun_mirror:-true}; then
        curl -fsSL --connect-timeout 10 $get_docker | $pre_sudo bash -s - --mirror Aliyun
    else
        curl -fsSL --connect-timeout 10 https://get.docker.com | $pre_sudo bash
    fi
    if ! _is_root; then
        _msg time "Add user \"$USER\" to group docker."
        $pre_sudo usermod -aG docker "$USER"
        echo '############################################'
        _msg red "!!!! Please logout $USER, and login again. !!!!"
        _msg red "And re-execute the above command."
        echo '############################################'
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
    ## revert aliyun linux
    if ${aliyun_os:-false}; then
        $pre_sudo sed -i -e '/^ID=/s/centos/alinux/' /etc/os-release
    fi
    $pre_sudo systemctl enable docker
    $pre_sudo systemctl start docker
}

_check_timezone() {
    ## change UTC to CST
    time_zone='Asia/Shanghai'
    _msg step "check timezone $time_zone"
    if timedatectl | grep -q "$time_zone"; then
        _msg time "Timezone is already set to $time_zone."
    else
        _msg time "Set timezone to $time_zone."
        $pre_sudo timedatectl set-timezone $time_zone
    fi
}

_check_laradock() {
    _msg step "check laradock"
    if [[ -d "$laradock_path" && -d "$laradock_path/.git" ]]; then
        _msg time "$laradock_path exist, git pull."
        (cd "$laradock_path" && git pull)
        return 0
    fi
    ## clone laradock
    _msg step "install laradock to $laradock_path/."
    mkdir -p "$laradock_path"

    git clone -b in-china --depth 1 $url_laradock_git "$laradock_path"
    ## jdk image, uid is 1000.(see spring/Dockerfile)
    if [[ "$(stat -c %u "$laradock_path/spring")" != 1000 ]]; then
        if $pre_sudo chown 1000:1000 "$laradock_path/spring"; then
            _msg time "OK: chown 1000:1000 $laradock_path/spring"
        else
            _msg red "FAIL: chown 1000:1000 $laradock_path/spring"
        fi
    fi
}

_check_laradock_env() {
    if [[ -f "$laradock_env" && "${force_update_env:-0}" -eq 0 ]]; then
        return 0
    fi
    _msg step "set laradock .env"
    pass_mysql="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
    pass_mysql_default="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
    pass_redis="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
    pass_redisadmin="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
    pass_gitlab="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
    ## change docker host ip
    docker_host_ip=$(/sbin/ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)

    _msg time "copy .env.example to .env, and set password"
    cp -vf "$laradock_env".example "$laradock_env"
    sed -i \
        -e "/^MYSQL_PASSWORD=/s/=.*/=$pass_mysql_default/" \
        -e "/MYSQL_ROOT_PASSWORD=/s/=.*/=$pass_mysql/" \
        -e "/MYSQL_VERSION=latest/s/=.*/=5.7/" \
        -e "/REDIS_PASSWORD=/s/=.*/=$pass_redis/" \
        -e "/PHPREDISADMIN_PASS=/s/=.*/=$pass_redisadmin/" \
        -e "/GITLAB_ROOT_PASSWORD=/s/=.*/=$pass_gitlab/" \
        -e "/PHP_VERSION=/s/=.*/=${php_ver}/" \
        -e "/CHANGE_SOURCE=/s/false/$IN_CHINA/" \
        -e "/DOCKER_HOST_IP=/s/=.*/=$docker_host_ip/" \
        -e "/GITLAB_HOST_SSH_IP=/s/=.*/=$docker_host_ip/" \
        "$laradock_env"

    for p in 80 443 3306 6379; do
        local listen_port=$p
        while ss -lntu4 | grep "LISTEN.*:$listen_port\ "; do
            _msg red "already LISTEN port: $listen_port ."
            listen_port=$((listen_port + 2))
            _msg yellow "try next port: $listen_port ..."
        done
        if [[ "$p" -eq 80 ]]; then
            sed -i -e "/^NGINX_HOST_HTTP_PORT=/s/=.*/=$listen_port/" "$laradock_env"
        fi
        if [[ "$p" -eq 443 ]]; then
            sed -i -e "/^NGINX_HOST_HTTPS_PORT=/s/=.*/=$listen_port/" "$laradock_env"
        fi
        if [[ "$p" -eq 3306 ]]; then
            sed -i -e "/^MYSQL_PORT=/s/=.*/=$listen_port/" "$laradock_env"
        fi
        if [[ "$p" -eq 6379 ]]; then
            sed -i -e "/^REDIS_PORT=/s/=.*/=$listen_port/" "$laradock_env"
        fi
    done

    ## set SHELL_OH_MY_ZSH=true
    echo "$SHELL" | grep -q zsh && sed -i -e "/SHELL_OH_MY_ZSH=/s/false/true/" "$laradock_env" || return 0
}

_reload_nginx() {
    cd "$laradock_path" || exit 1
    for i in {1..10}; do
        if $dco exec -T nginx nginx -t; then
            $dco exec -T nginx nginx -s reload
            break
        else
            _msg time "[$((i * 2))] reload nginx err."
        fi
        sleep 2
    done
}

_set_nginx_php() {
    ## setup php upstream
    sed -i -e 's/127\.0\.0\.1/php-fpm/g' "$laradock_path/nginx/sites/d.php.inc"
}

_set_nginx_java() {
    ## setup java upstream
    sed -i -e 's/127\.0\.0\.1/spring/g' "$laradock_path/nginx/sites/d.java.inc"
}

_set_env_php_ver() {
    sed -i \
        -e "/PHP_VERSION=/s/=.*/=${php_ver}/" \
        -e "/CHANGE_SOURCE=/s/false/true/" \
        "$laradock_env"
}

_get_image() {
    image_name=$1
    if ${is_php:-false}; then
        if docker images | grep -E "laradock-$image_name|laradock_$image_name"; then
            if [[ ${overwrite_php_image:-false} == true ]]; then
                echo "download php image..."
            else
                return 0
            fi
        fi
    else
        if ${get_image_cdn:-false}; then
            echo "get image from cdn ..."
        else
            return 0
        fi
    fi

    _msg step "get image laradock-$image_name"
    image_save=/tmp/laradock-${image_name}.tar.gz
    curl -Lo "$image_save" "${url_image}"
    _msg time "docker load image..."
    docker load <"$image_save"

    if docker --version | grep -q "version 19"; then
        docker tag "laradock-$image_name" "laradock_$image_name"
    else
        if docker images | grep "laradock_$image_name"; then
            docker tag "laradock_$image_name" "laradock-$image_name"
        fi
    fi
}

_set_file_mode() {
    _check_sudo
    for d in "$laradock_path"/../*/; do
        [[ "$d" == *laradock/ ]] && continue
        find "$d" | while read -r line; do
            if [[ "$line" == *config/app.php ]]; then
                grep -q 'app_debug.*true' "$line" && $pre_sudo sed -i -e '/app_debug/s/true/false/' "$line"
            fi
            if [[ "$line" == *config/log.php ]]; then
                grep -q "'level'.*\[\]\," "$line" && $pre_sudo sed -i -e "/'level'/s/\[/\['warning'/" "$line"
            fi
        done
    done
}

_install_zsh() {
    _msg step "install oh my zsh"
    _check_sudo

    if [[ -d "$HOME"/.oh-my-zsh ]]; then
        _msg warn "Found $HOME/.oh-my-zsh, skip."
    else
        if ${IN_CHINA:-true}; then
            git clone --depth 1 https://gitee.com/mirrors/ohmyzsh.git "$HOME"/.oh-my-zsh
        else
            bash -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        fi
        cp -vf "$HOME"/.oh-my-zsh/templates/zshrc.zsh-template "$HOME"/.zshrc
        sed -i -e "/^ZSH_THEME/s/robbyrussell/ys/" "$HOME"/.zshrc
        sed -i -e '/^plugins=.*/s//plugins=\(git z extract docker docker-compose\)/' ~/.zshrc
    fi
    if [[ "${apt_update:-0}" -eq 1 ]] && $cmd install -yqq fzf; then
        sed -i -e "/^plugins=\(git\)/s/git/git z extract fzf docker-compose/" "$HOME"/.zshrc
    fi
}

_start_manual() {
    _msg step "Start docker service manually..."
    _msg info '#########################################'
    _msg info "\n cd $laradock_path && $dco up -d $args \n"
    _msg info '#########################################'
    _msg "END"
}

_start_auto() {
    if [ "${#args[@]}" -gt 0 ]; then
        _msg step "Start docker service automatically..."
    else
        _msg warn "no arguments for docker service"
        return
    fi
    cd "$laradock_path" || exit 1
    $dco up -d "${args[@]}"
    ## wait startup
    for arg in "${args[@]}"; do
        for i in {1..10}; do
            if $dco ps | grep "$arg"; then
                break
            else
                sleep 2
            fi
        done
    done
}

_test_nginx() {
    _reload_nginx
    nginx_port=$(awk -F= '/NGINX_HOST_HTTP_PORT/ {print $2}' "$laradock_env")
    _msg time "test nginx $1 ..."
    for i in {1..10}; do
        if curl --connect-timeout 3 "http://localhost:$nginx_port/${1}"; then
            break
        else
            _msg time "[$((i * 2))] test nginx err."
            sleep 2
        fi
    done
}

_test_php() {
    _check_sudo

    path_nginx_root="$laradock_path/../html"
    $pre_sudo chown "$USER:$USER" "$path_nginx_root"
    if [[ ! -f "$path_nginx_root/test.php" ]]; then
        _msg time "Create test.php"
        $pre_sudo cp -avf "$laradock_path/php-fpm/root/opt/test.php" "$path_nginx_root/test.php"
        # shellcheck disable=1090
        source "$laradock_env" 2>/dev/null
        sed -i \
            -e "s/ENV_REDIS_PASSWORD/$REDIS_PASSWORD/" \
            -e "s/ENV_MYSQL_USER/$MYSQL_USER/" \
            -e "s/ENV_MYSQL_PASSWORD/$MYSQL_PASSWORD/" \
            "$path_nginx_root/test.php"
    fi

    # _set_nginx_php

    _test_nginx "test.php"
}

_test_java() {
    _msg time "Test spring..."
    if $dco ps | grep "spring.*Up"; then
        _msg time "container spring is up"
    else
        _msg time "container spring is down"
    fi
}

_get_redis_mysql_info() {
    echo
    grep '^REDIS_' "$laradock_env" | sed -n '1,12 p' | grep -v 'REDIS_.*2='
    echo
    grep -E '^DB_HOST|^MYSQL_' "$laradock_env" | grep -v MYSQL_ROOT_PASSWORD | sed -n '1,6 p'
}

_mysql_cli() {
    _msg time "exec mysql"
    cd "$laradock_path"
    db_default=$(awk -F= '/^MYSQL_DATABASE=/ {print $2}' "$laradock_env")
    user_default=$(awk -F= '/^MYSQL_USER=/ {print $2}' "$laradock_env")
    password_default=$(awk -F= '/^MYSQL_PASSWORD=/ {print $2}' "$laradock_env")
    $dco exec -T mysql bash -c "LANG=C.UTF-8 mysql $db_default -u $user_default -p$password_default"
}

_redis_cli() {
    _msg time "exec redis"
    cd "$laradock_path"
    password_default=$(awk -F= '/^REDIS_PASSWORD=/ {print $2}' "$laradock_env")
    $dco exec redis bash -c "redis-cli --no-auth-warning -a $password_default"
}

_install_lsyncd() {
    _msg time "install lsyncd"
    _check_sudo
    if _command_exists lsyncd; then
        _msg warn "Found command lsyncd, skip."
        return
    else
        $cmd install -y lsyncd
    fi

    _msg time "new lsyncd.conf.lua"
    lsyncd_conf=/etc/lsyncd/lsyncd.conf.lua
    if [ ! -d /etc/lsyncd/ ]; then
        $pre_sudo mkdir /etc/lsyncd
        $pre_sudo cp "$laradock_path"/usvn$lsyncd_conf $lsyncd_conf
        [[ "$USER" == "root" ]] || $pre_sudo sed -i "s@/root/docker@$HOME/docker@" $lsyncd_conf
    fi

    _msg time "new key, ssh-keygen"
    id_file="$HOME/.ssh/id_ed25519"
    [ -f "$id_file" ] || ssh-keygen -t ed25519 -f "$id_file" -N ''
    while read -rp "Enter ssh host IP [${count:=1}] (enter q break): " ssh_host_ip; do
        [[ -z "$ssh_host_ip" || "$ssh_host_ip" == q ]] && break
        _msg time "ssh-copy-id -i $id_file root@$ssh_host_ip"
        ssh-copy-id -i "$id_file" "root@$ssh_host_ip"
        _msg time "update $lsyncd_conf"
        line_num=$(grep -n '^targets' $lsyncd_conf | awk -F: '{print $1}')
        $pre_sudo sed -i -e "$line_num a '$ssh_host_ip:$HOME/docker/html/'," $lsyncd_conf
        count=$((count + 1))
    done
}

_upgrade_java() {
    curl -fL $url_fly_cdn/spring.tar.gz | tar -C "$laradock_path"/ vzx
    $dco stop spring
    $dco rm -f
    $dco up -d spring
}

_upgrade_php() {
    curl -fL $url_fly_cdn/tp.tar.gz | tar -C "$laradock_path"/../html/ vzx
}

_usage() {
    echo "
Usage: $0 [parameters ...]

Parameters:
    -h, --help          Show this help message.
    -v, --version       Show version info.
    info                get mysql redis info
    php                 install php-fpm 7.1
    build               build php image
    java                install jdk / spring
    mysql               exec into mysql cli
    perm                set file permission
    lsync               setup lsyncd
"
    exit 1
}

_build_image_nginx() {
    build_opt="$build_opt --build-arg CHANGE_SOURCE=${IN_CHINA} --build-arg IN_CHINA=${IN_CHINA} --build-arg LARADOCK_PHP_VERSION=$php_ver"
    image_tag_base=fly/nginx:base
    image_tag=fly/nginx

    $build_opt -t "$image_tag_base" -f Dockerfile.base .

    echo "FROM $image_tag_base" >Dockerfile
    $build_opt -t "$image_tag" .
}

_build_image_php() {
    build_opt="$build_opt --build-arg CHANGE_SOURCE=${IN_CHINA} --build-arg IN_CHINA=${IN_CHINA} --build-arg LARADOCK_PHP_VERSION=$php_ver"
    image_tag_base=fly/php:${php_ver}-base
    image_tag=fly/php:${php_ver}

    root_opt=root/opt
    [ -d root ] || mkdir -p $root_opt
    if ${build_remote:-false}; then
        curl -fLo Dockerfile.base $url_laradock_raw/php-fpm/Dockerfile.base
        curl -fLo $root_opt/nginx.conf $url_laradock_raw/php-fpm/$root_opt/nginx.conf
        curl -fLo $root_opt/build.sh $url_laradock_raw/php-fpm/$root_opt/build.sh
        curl -fLo $root_opt/onbuild.sh $url_laradock_raw/php-fpm/$root_opt/onbuild.sh
        curl -fLo $root_opt/run.sh $url_laradock_raw/php-fpm/$root_opt/run.sh
    fi

    if docker images | grep "fly/php.*${php_ver}-base"; then
        _msg time "ignore build base image."
    else
        if ${build_remote:-false}; then
            $build_opt -t "$image_tag_base" -f Dockerfile.base .
        else
            $build_opt -t "$image_tag_base" -f php-fpm/Dockerfile.base php-fpm/
        fi
    fi
    if ${build_remote:-false}; then
        echo "FROM $image_tag_base" >Dockerfile
        $build_opt -t "$image_tag" .
    else
        echo "FROM $image_tag_base" >php-fpm/Dockerfile
        $build_opt -t "$image_tag" -f php-fpm/Dockerfile php-fpm/
    fi
}

_build_image_java() {
    build_opt="$build_opt --build-arg CHANGE_SOURCE=${IN_CHINA} --build-arg IN_CHINA=${IN_CHINA}"
    # image_tag_base=fly/spring:base
    image_tag=fly/spring

    [ -d root ] || mkdir -p root/opt
    if ${build_remote:-false}; then
        curl -fLo Dockerfile $url_deploy_raw/conf/dockerfile/Dockerfile.java
        curl -fLo root/opt/build.sh $url_deploy_raw/conf/dockerfile/root/build.sh
        curl -fLo root/opt/run.sh $url_deploy_raw/conf/dockerfile/root/run.sh
    fi
    # $build_opt -t "$image_tag_base" -f Dockerfile.base .

    $build_opt -t "$image_tag" .
}

_set_args() {
    IN_CHINA=true
    php_ver=7.1

    args=()
    if [ "$#" -eq 0 ]; then
        _msg warn "not found arguments, with default args \"nginx php-fpm spring mysql redis\"."
        args=(nginx php-fpm spring mysql redis)
    fi
    while [ "$#" -gt 0 ]; do
        case "${1}" in
        mysql)
            args+=(mysql)
            ;;
        redis)
            args+=(redis)
            set_sysctl=true
            ;;
        nginx)
            args+=(nginx)
            ;;
        java | spring)
            args+=(spring)
            ;;
        php | php-fpm | fpm)
            args+=(php-fpm)
            ;;
        [0-9].[0-9])
            php_ver=${1:-7.1}
            ;;
        upgrade)
            [[ "${args[*]}" == *php-fpm* ]] && exec_upgrade_php=true
            [[ "${args[*]}" == *spring* ]] && exec_upgrade_java=true
            enable_check=false
            ;;
        github | not-china | not-cn | ncn)
            IN_CHINA=false
            aliyun_mirror=false
            ;;
        build)
            exec_build_image=true
            ;;
        build-remote)
            build_remote=true
            ;;
        build-nocache | nocache)
            build_opt="docker build --no-cache"
            ;;
        install-docker-without-aliyun)
            aliyun_mirror=false
            ;;
        get-image-cdn)
            get_image_cdn=true
            ;;
        overwrite-php-image)
            overwrite_php_image=true
            ;;
        man | manual)
            manual_start=true
            ;;
        gitlab | git)
            args+=(gitlab)
            ;;
        svn | usvn)
            args+=(usvn)
            ;;
        install-zsh | zsh)
            exec_install_zsh=true
            enable_check=true
            ;;
        install-lsyncd | lsync | lsyncd)
            exec_install_lsyncd=true
            enable_check=false
            ;;
        info)
            exec_get_redis_mysql_info=true
            enable_check=false
            ;;
        mysql-cli)
            exec_mysql_cli=true
            enable_check=false
            ;;
        redis-cli)
            exec_redis_cli=true
            enable_check=false
            ;;
        test)
            exec_test_nginx=true
            exec_test_php=true
            enable_check=false
            ;;
        reset | clean | clear)
            exec_reset=true
            enable_check=false
            ;;
        *)
            _usage
            ;;
        esac
        shift
    done
}

main() {
    SECONDS=0
    _set_args "$@"
    set -e
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="${me_path}/${me_name}.log"

    url_fly_cdn="http://cdn.flyh6.com/docker"

    if ${IN_CHINA:-true}; then
        url_laradock_git=https://gitee.com/xiagw/laradock.git
        url_laradock_raw=https://gitee.com/xiagw/laradock/raw/in-china
        url_deploy_raw=https://gitee.com/xiagw/deploy.sh/raw/main
    else
        url_laradock_git=https://github.com/xiagw/laradock.git
        url_laradock_raw=https://github.com/xiagw/laradock/raw/main
        url_deploy_raw=https://github.com/xiagw/deploy.sh/raw/main
    fi

    laradock_home="$HOME"/docker/laradock
    laradock_current="$me_path"
    if [[ -f "$laradock_current/fly.sh" && -f "$laradock_current/.env.example" ]]; then
        ## 从本机已安装目录执行 fly.sh
        laradock_path="$laradock_current"
    elif [[ -f "$laradock_home/fly.sh" && -f "$laradock_home/.env.example" ]]; then
        laradock_path=$laradock_home
    else
        ## 从远程执行 fly.sh , curl "remote_url" | bash -s args
        laradock_path="$laradock_current"/docker/laradock
    fi

    laradock_env="$laradock_path"/.env

    if ${exec_get_redis_mysql_info:-false}; then
        _get_redis_mysql_info
        return
    fi
    if ${exec_upgrade_java:-false}; then
        _upgrade_java
        return
    fi
    if ${exec_upgrade_php:-false}; then
        _upgrade_php
        return
    fi

    _check_dependence

    if ${exec_install_zsh:-false}; then
        _install_zsh
        return
    fi
    if ${exec_install_lsyncd:-false}; then
        _install_lsyncd
        return
    fi

    dco="docker compose"
    if $dco version; then
        _msg info "$dco ready."
    else
        if _command_exists docker-compose; then
            dco="docker-compose"
            dco_ver=$(docker-compose -v | awk '{gsub(/[,\.]/,""); print int($3)}')
            if [[ "$dco_ver" -lt 1190 ]]; then
                _msg warn "docker-compose version is too low."
            fi
        fi
    fi

    if ${exec_reset:-false}; then
        _msg step "reset docker"
        (
            cd "$laradock_path"
            $dco stop
            $dco rm -f
        )
        _check_sudo
        $pre_sudo rm -rf "$laradock_path" "$laradock_path/../../laradock-data/mysql"
        return
    fi
    if ${exec_build_image:-false}; then
        build_opt="${build_opt:-docker build}"
        if [[ "${args[*]}" == *nginx* ]]; then
            _build_image_nginx
        fi
        if [[ "${args[*]}" == *php* ]]; then
            _build_image_php
        fi
        if [[ "${args[*]}" == *spring* ]]; then
            _build_image_java
        fi
        if ${build_remote:-false}; then
            _msg warn "safe remove \"rm -rf root/ Dockerfile\"."
        fi
        return
    fi

    if ${exec_mysql_cli:-false}; then
        _mysql_cli
        return
    fi

    if ${exec_redis_cli:-false}; then
        _redis_cli
        return
    fi

    if ${enable_check:-true}; then
        _check_sudo
        _check_timezone
        _check_docker
        _check_laradock
        _check_laradock_env
    fi

    ## if install docker and add normal user (not root) to group "docker"
    if ${need_logout:-false}; then
        return
    fi

    _msg step "check docker image..."
    for i in "${args[@]}"; do
        case $i in
        nginx)
            url_image="$url_fly_cdn/laradock-nginx.tar.gz"
            _get_image nginx
            exec_test_nginx=true
            ;;
        mysql)
            cat >"$laradock_path"/mysql/docker-entrypoint-initdb.d/create.defautldb.sql <<'EOF'
CREATE DATABASE IF NOT EXISTS `defaultdb` COLLATE 'utf8mb4_general_ci' ;
GRANT ALL ON `defaultdb`.* TO 'defaultdb'@'%' ;
CREATE DATABASE IF NOT EXISTS `flydev` COLLATE 'utf8mb4_general_ci' ;
GRANT ALL ON `flydev`.* TO 'flydev'@'%' ;
GRANT ALL ON `defaultdb`.* TO 'flydev'@'%' ;
CREATE DATABASE IF NOT EXISTS `flytest` COLLATE 'utf8mb4_general_ci' ;
GRANT ALL ON `flytest`.* TO 'flytest'@'%' ;
GRANT ALL ON `defaultdb`.* TO 'flytest'@'%' ;
CREATE DATABASE IF NOT EXISTS `flyprod` COLLATE 'utf8mb4_general_ci' ;
GRANT ALL ON `flyprod`.* TO 'flyprod'@'%' ;
GRANT ALL ON `defaultdb`.* TO 'flyprod'@'%' ;
EOF
            if [ ! -d "$laradock_path"/../../laradock-data/mysqlbak ]; then
                $pre_sudo mkdir -p "$laradock_path"/../../laradock-data/mysqlbak
                $pre_sudo chown 1005 "$laradock_path"/../../laradock-data/mysqlbak
            fi
            url_image="$url_fly_cdn/laradock-mysql.tar.gz"
            _get_image mysql
            url_image="$url_fly_cdn/laradock-mysqlbak.tar.gz"
            _get_image mysqlbak
            ;;
        redis)
            url_image="$url_fly_cdn/laradock-redis.tar.gz"
            _get_image redis
            ;;
        spring)
            url_image="$url_fly_cdn/laradock-spring.tar.gz"
            _get_image spring
            # _set_file_mode
            _set_nginx_java
            exec_test_java=1
            ;;
        php*)
            url_image="$url_fly_cdn/laradock-php-fpm.${php_ver}.tar.gz"
            _set_env_php_ver
            # _set_file_mode
            is_php=true
            _get_image php-fpm
            unset is_php
            exec_test_php=true
            ;;
        esac
    done

    if ${manual_start:-false}; then
        _start_manual
        return
    else
        _start_auto
    fi

    _msg step "check service"

    if ${exec_test_nginx:-false}; then
        _test_nginx
    fi

    if ${exec_test_php:-false}; then
        _test_php
    fi

    if ${exec_test_java:-false}; then
        _test_java
    fi
}

main "$@"
