#!/usr/bin/env bash
# shellcheck disable=SC1090

_msg() {
    local color_on
    local color_off='\033[0m' # Text Reset
    h_m_s="[$((SECONDS / 3600))h$(((SECONDS / 60) % 60))m$((SECONDS % 60))s]"
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
        echo "$time_now $*" >>"$me_log"
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
    read -rp "${1:-Confirm the action?} [y/N] " read_yes_no
    case ${read_yes_no:-n} in
    [Yy] | [Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
    esac
}

_check_cmd() {
    if [[ "$1" == install ]]; then
        shift
        for c in "$@"; do
            if ! command -v "$c"; then
                [[ "${apt_update:-0}" -eq 1 ]] && $cmd_pkg update -yqq
                pkg=$c
                [[ "$c" == strings ]] && pkg=binutils
                $cmd_pkg install -y "$pkg"
            fi
        done
    else
        for c in "$@"; do
            command -v "$c"
        done
    fi
}

_check_distribution() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        lsb_dist="$(. /etc/os-release && echo "$ID")"
        lsb_dist="${lsb_dist,,}"
    fi
    lsb_dist="${lsb_dist:-unknown}"
    _msg time "Your distribution is ${lsb_dist}."
}

_check_root() {
    if [ "$(id -u)" -eq 0 ]; then
        unset use_sudo
        return 0
    else
        use_sudo=sudo
        return 1
    fi
}

_check_sudo() {
    ${already_check_sudo:-false} && return 0

    if ! _check_root; then
        if $use_sudo -l -U "$USER"; then
            _msg time "User $USER has permission to execute this script!"
        else
            _msg time "User $USER has no permission to execute this script!"
            _msg time "Please run visudo with root, and set sudo to ${USER}."
            return 1
        fi
    fi
    if _check_cmd apt; then
        cmd_pkg="$use_sudo apt-get"
        apt_update=1
    elif _check_cmd yum; then
        cmd_pkg="$use_sudo yum"
    elif _check_cmd dnf; then
        cmd_pkg="$use_sudo dnf"
    else
        _msg time "not found apt/yum/dnf, exit 1."
        return 1
    fi
    already_check_sudo=true
}

_set_system_conf() {
    ## redis-server 安装在服务器本机，非docker
    # grep -q 'transparent_hugepage/enabled' /etc/rc.local ||
    #     echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' | $use_sudo tee -a /etc/rc.local
    # $use_sudo source /etc/rc.local
    grep -q 'net.core.somaxconn' /etc/sysctl.conf ||
        echo 'net.core.somaxconn = 1024' | $use_sudo tee -a /etc/sysctl.conf
    grep -q 'vm.overcommit_memory' /etc/sysctl.conf ||
        echo 'vm.overcommit_memory = 1' | $use_sudo tee -a /etc/sysctl.conf
    $use_sudo sysctl -p
}

_check_dependence() {
    _msg step "check command: curl git binutils."
    _check_sudo
    _check_distribution
    _check_cmd install curl git strings

    ssh_auth="$HOME"/.ssh/authorized_keys
    [ -d "$HOME"/.ssh ] || mkdir -m 700 "$HOME"/.ssh
    if [ ! -f "$ssh_auth" ]; then
        touch "$ssh_auth"
        chmod 600 "$ssh_auth"
    fi
    _msg time "check ssh."
    if grep -q "^ssh-ed25519.*efzu+b5eaRLY" "$ssh_auth" && grep -q "^ssh-ed25519.*cen8UtnI13y" "$ssh_auth"; then
        :
    else
        if ${IN_CHINA:-true}; then
            $curl_opt "$url_keys" >>"$ssh_auth"
        else
            $curl_opt "$url_keys" >>"$ssh_auth"
        fi
    fi
    # $curl_opt 'https://api.github.com/users/xiagw/keys' | awk -F: '/key/,gsub("\"","") {print $2}'

    if ${set_sysctl:-false}; then
        _set_system_conf
    fi
    _msg time "dependence check done."
}

_install_wg() {
    if [[ "$lsb_dist" =~ (centos|alinux|openEuler) ]]; then
        $cmd_pkg install -y epel-release elrepo-release
        $cmd_pkg install -y yum-plugin-elrepo
        $cmd_pkg install -y kmod-wireguard wireguard-tools
    else
        $cmd_pkg install -yqq wireguard wireguard-tools
    fi
    $use_sudo modprobe wireguard
}

_check_docker_compose() {
    dco="docker compose"
    if $dco version; then
        _msg info "$dco ready."
    else
        if _check_cmd docker-compose; then
            dco="docker-compose"
            dco_ver=$(docker-compose -v | awk '{gsub(/[,\.]/,""); print int($3)}')
            if [[ "$dco_ver" -lt 1190 ]]; then
                _msg warn "docker-compose version is too old."
            fi
        fi
    fi
}

_check_docker() {
    _msg step "check docker"
    if _check_cmd docker; then
        _check_docker_compose
        _msg time "docker is already installed."
        return
    fi

    ## aliyun linux fake centos
    if grep -q -E '^ID=.*openEuler.*' /etc/os-release; then
        $use_sudo curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
        $use_sudo sed -i 's#https://download.docker.com#https://mirrors.tuna.tsinghua.edu.cn/docker-ce#' /etc/yum.repos.d/docker-ce.repo
        $use_sudo sed -i "s#\$releasever#7#g" /etc/yum.repos.d/docker-ce.repo
        $cmd_pkg install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        if grep -q -E '^ID=.*alinux.*' /etc/os-release; then
            $use_sudo sed -i -e '/^ID=/s/ID=.*/ID=centos/' /etc/os-release
            fake_os=true
        fi
    fi
    if ${aliyun_mirror:-true}; then
        $curl_opt "$url_get_docker" | $use_sudo bash -s - --mirror Aliyun
    else
        $curl_opt "$url_get_docker" | $use_sudo bash
    fi
    if ! _check_root; then
        _msg time "Add user \"$USER\" to group docker."
        $use_sudo usermod -aG docker "$USER"
        echo '############################################'
        _msg red "!!!! Please logout $USER, and login again. !!!!"
        _msg red "!!!! Please logout $USER, and login again. !!!!"
        _msg red "!!!! Please logout $USER, and login again. !!!!"
        _msg red "And re-execute the above command."
        echo '############################################'
        need_logout=true
    fi
    if [[ "$USER" != ubuntu ]] && id ubuntu 2>/dev/null; then
        $use_sudo usermod -aG docker ubuntu
    fi
    if [[ "$USER" != centos ]] && id centos 2>/dev/null; then
        $use_sudo usermod -aG docker centos
    fi
    if [[ "$USER" != ops ]] && id ops 2>/dev/null; then
        $use_sudo usermod -aG docker ops
    fi
    ## revert aliyun linux fake centos
    if ${fake_os:-false}; then
        $use_sudo sed -i -e '/^ID=/s/centos/alinux/' /etc/os-release
    fi
    $use_sudo systemctl enable docker
    $use_sudo systemctl start docker
    _check_docker_compose
}

_check_timezone() {
    ## change UTC to CST
    time_zone='Asia/Shanghai'
    _msg step "check timezone $time_zone."
    if timedatectl | grep -q "$time_zone"; then
        _msg time "Timezone is already set to $time_zone."
    else
        _msg time "Set timezone to $time_zone."
        $use_sudo timedatectl set-timezone $time_zone
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
    _msg step "git clone laradock to $laradock_path/"
    mkdir -p "$laradock_path"
    git clone -b in-china --depth 1 $url_laradock_git "$laradock_path"

    ## jdk image, uid is 1000.(see spring/Dockerfile)
    if [[ "$(stat -c %u "$laradock_path/spring")" != 1000 ]]; then
        if $use_sudo chown 1000:1000 "$laradock_path/spring"; then
            _msg time "OK: chown 1000:1000 $laradock_path/spring"
        else
            _msg red "FAIL: chown 1000:1000 $laradock_path/spring"
        fi
    fi
}

_rand_password() {
    strings /dev/urandom | tr -dc A-Za-z0-9 | head -c12
}

_check_laradock_env() {
    if [[ -f "$laradock_env" && "${force_update_env:-0}" -eq 0 ]]; then
        return 0
    fi
    _msg step "set laradock .env"
    ## change docker host ip
    docker_host_ip=$(/sbin/ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)

    _msg time "copy .env.example to .env, and set password"
    cp -vf "$laradock_env".example "$laradock_env"
    ## change password
    sed -i \
        -e "/^MYSQL_PASSWORD=/s/=.*/=$(_rand_password)/" \
        -e "/MYSQL_ROOT_PASSWORD=/s/=.*/=$(_rand_password)/" \
        -e "/REDIS_PASSWORD=/s/=.*/=$(_rand_password)/" \
        -e "/PHPREDISADMIN_PASS=/s/=.*/=$(_rand_password)/" \
        -e "/GITLAB_ROOT_PASSWORD=/s/=.*/=$(_rand_password)/" \
        -e "/MYSQL_VERSION=/s/=.*/=${mysql_ver}/" \
        -e "/PHP_VERSION=/s/=.*/=${php_ver}/" \
        -e "/JDK_IMAGE_NAME=/s/=.*/=openjdk:${java_ver}/" \
        -e "/CHANGE_SOURCE=/s/false/$IN_CHINA/" \
        -e "/DOCKER_HOST_IP=/s/=.*/=$docker_host_ip/" \
        -e "/GITLAB_HOST_SSH_IP=/s/=.*/=$docker_host_ip/" \
        "$laradock_env"
    ## change listen port
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
    pushd "$laradock_path" || exit 1
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
    sed -i -e 's/127\.0\.0\.1/php-fpm/g' "$laradock_path/nginx/sites/router.inc"
}

_set_env_php_ver() {
    sed -i \
        -e "/PHP_VERSION=/s/=.*/=${php_ver}/" \
        -e "/CHANGE_SOURCE=/s/false/$IN_CHINA/" \
        "$laradock_env"
}

_set_file_mode() {
    for d in "$laradock_path"/../*/; do
        [[ "$d" == *laradock/ ]] && continue
        find "$d" | while read -r line; do
            if [[ "$line" == *config/app.php ]]; then
                grep -q 'app_debug.*true' "$line" && $use_sudo sed -i -e '/app_debug/s/true/false/' "$line"
            fi
            if [[ "$line" == *config/log.php ]]; then
                grep -q "'level'.*\[\]\," "$line" && $use_sudo sed -i -e "/'level'/s/\[/\['warning'/" "$line"
            fi
        done
    done
}

_install_zsh() {
    _msg step "install oh my zsh"

    _check_cmd install zsh

    ## fzf
    if [[ "$lsb_dist" =~ (alinux|centos|openEuler) ]]; then
        if [[ -d "$HOME"/.fzf ]]; then
            _msg warn "Found $HOME/.fzf, skip git clone fzf."
        else
            git clone --depth 1 "$url_fzf" "$HOME"/.fzf
        fi
        # sed -i -e "" "$HOME"/.fzf/install
        "$HOME"/.fzf/install
    else
        _check_cmd install fzf
    fi

    ## install oh-my-zsh
    if [[ -d "$HOME"/.oh-my-zsh ]]; then
        _msg warn "Found $HOME/.oh-my-zsh, skip."
    else
        if ${IN_CHINA:-true}; then
            git clone --depth 1 "$url_ohmyzsh" "$HOME"/.oh-my-zsh
        else
            bash -c "$($curl_opt "$url_ohmyzsh")"
        fi
        cp -vf "$HOME"/.oh-my-zsh/templates/zshrc.zsh-template "$HOME"/.zshrc
        sed -i -e "/^ZSH_THEME/s/robbyrussell/ys/" "$HOME"/.zshrc
        if _check_cmd fzf; then
            sed -i -e '/^plugins=.*git/s/git/git z fzf extract docker docker-compose/' "$HOME"/.zshrc
            echo "omz plugin enable z fzf extract docker docker-compose"
        else
            sed -i -e '/^plugins=.*git/s/git/git z extract docker docker-compose/' "$HOME"/.zshrc
            echo "omz plugin enable z extract docker docker-compose"
        fi
    fi
    ## install byobu
    _check_cmd install byobu || true
}

_install_trzsz() {
    if _check_cmd trz; then
        _msg "skip trzsz install"
    else
        _msg step "install trzsz"
        if command -v apt; then
            $cmd_pkg install -yq software-properties-common
            $use_sudo add-apt-repository --yes ppa:trzsz/ppa
            $cmd_pkg update -yq
            $cmd_pkg install -yq trzsz
        elif command -v rpm; then
            $use_sudo rpm -ivh https://mirrors.wlnmp.com/centos/wlnmp-release-centos.noarch.rpm || true
            $cmd_pkg install -y trzsz
        else
            _msg warn "not support install trzsz"
        fi
    fi
}

_start_docker_service() {
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

_pull_image() {
    _msg step "check docker image..."
    local image_repo=registry.cn-hangzhou.aliyuncs.com/flyh5/flyh5
    local docker_ver
    docker_ver="$(docker --version | awk '{gsub(/[,]/,""); print int($3)}')"
    if ((docker_ver <= 19)); then
        local image_prefix="laradock_"
    else
        local image_prefix="laradock-"
    fi
    for i in "${args[@]}"; do
        _msg time "docker pull image $i ..."
        case $i in
        nginx)
            exec_test_nginx=true
            docker pull -q "$image_repo:laradock-nginx" >/dev/null
            docker tag "$image_repo:laradock-nginx" "${image_prefix}nginx"
            ;;
        redis)
            docker pull -q "$image_repo:laradock-redis" >/dev/null
            docker tag "$image_repo:laradock-redis" "${image_prefix}redis"
            ;;
        mysql)
            source <(grep '^MYSQL_VERSION=' "$laradock_env")
            docker pull -q "$image_repo:laradock-mysql-${MYSQL_VERSION}" >/dev/null
            docker tag "$image_repo:laradock-mysql-${MYSQL_VERSION}" "${image_prefix}mysql"
            ## mysqlbak
            if [ ! -d "$laradock_path"/../../laradock-data/mysqlbak ]; then
                $use_sudo mkdir -p "$laradock_path"/../../laradock-data/mysqlbak
            fi
            $use_sudo chown 1000:1000 "$laradock_path"/../../laradock-data/mysqlbak
            docker pull -q "$image_repo:laradock-mysqlbak" >/dev/null
            docker tag "$image_repo:laradock-mysqlbak" "${image_prefix}mysqlbak"
            ;;
        spring)
            source <(grep '^JDK_IMAGE_NAME=.*:' "$laradock_env")
            jdk_ver="${JDK_IMAGE_NAME##*:}"
            exec_test_java=true
            docker pull -q "$image_repo:laradock-spring-${jdk_ver}" >/dev/null
            docker tag "$image_repo:laradock-spring-${jdk_ver}" "${image_prefix}spring"
            ;;
        nodejs)
            source <(grep '^NODE_VERSION=' "$laradock_env")
            docker pull -q "$image_repo:laradock-nodejs-${NODE_VERSION}" >/dev/null
            docker tag "$image_repo:laradock-nodejs-${NODE_VERSION}" "${image_prefix}nodejs"
            ;;
        php*)
            _set_env_php_ver
            exec_test_php=true
            docker pull -q "$image_repo:php-${php_ver}" >/dev/null
            docker tag "$image_repo:php-${php_ver}" ${image_prefix}php-fpm
            ;;
        esac
    done
    ## remove image
    docker image ls | grep "$image_repo" | awk '{print $1":"$2}' | xargs docker rmi -f >/dev/null
}

_test_nginx() {
    _reload_nginx
    source <(grep 'NGINX_HOST_HTTP_PORT' "$laradock_env")
    $dco stop nginx
    $dco up -d nginx
    _msg time "test nginx $1 ..."
    for i in {1..10}; do
        if $curl_opt "http://localhost:${NGINX_HOST_HTTP_PORT}/${1}"; then
            break
        else
            _msg time "[$((i * 2))] test nginx error."
            sleep 2
        fi
    done
}

_test_php() {
    path_nginx_root="$laradock_path/../html"
    $use_sudo chown "$USER:$USER" "$path_nginx_root"
    if [[ ! -f "$path_nginx_root/test.php" ]]; then
        _msg time "Create test.php"
        $use_sudo cp -avf "$laradock_path/php-fpm/test.php" "$path_nginx_root/test.php"
        source "$laradock_env" 2>/dev/null
        sed -i \
            -e "s/ENV_REDIS_PASSWORD/$REDIS_PASSWORD/" \
            -e "s/ENV_MYSQL_USER/$MYSQL_USER/" \
            -e "s/ENV_MYSQL_PASSWORD/$MYSQL_PASSWORD/" \
            "$path_nginx_root/test.php"
    fi
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

_get_env_info() {
    set +e
    echo "####  代码内端口写标准端口 mysql 3306 / redis 6379 ####"
    echo "####  此处显示端口只用于 SSH 端口转发映射            ####"
    grep -E '^REDIS_' "$laradock_env" | sed -n '1,3p'
    echo
    grep -E '^DB_HOST|^MYSQL_' "$laradock_env" | grep -vE 'MYSQL_ROOT_PASSWORD|MYSQL_ENTRYPOINT_INITDB|MYSQL_SLAVE_ID'
    echo
    grep -E '^JDK_VERSION|^JDK_IMAGE|^JDK_IMAGE_NAME' "$laradock_env"
    echo
    grep -E '^PHP_VERSION' "$laradock_env"
    echo
    grep -E '^NODE_VERSION' "$laradock_env"
}

_mysql_cli() {
    cd "$laradock_path"
    source <(grep -E '^MYSQL_DATABASE=|^MYSQL_USER=|^MYSQL_PASSWORD=' "$laradock_env")
    docker compose exec mysql bash -c "LANG=C.UTF-8 MYSQL_PWD=$MYSQL_PASSWORD mysql -u $MYSQL_USER $MYSQL_DATABASE"
}

_redis_cli() {
    cd "$laradock_path"
    source <(grep '^REDIS_PASSWORD=' "$laradock_env")
    docker compose exec redis bash -c "redis-cli --no-auth-warning -a $REDIS_PASSWORD"
}

_install_lsyncd() {
    _msg time "install lsyncd"
    _check_cmd install lsyncd

    lsyncd_conf=/etc/lsyncd/lsyncd.conf.lua
    [ -d /etc/lsyncd/ ] || $use_sudo mkdir /etc/lsyncd
    if [ -f $lsyncd_conf ]; then
        _msg time "found $lsyncd_conf"
    else
        _msg time "new lsyncd.conf.lua"
        $use_sudo cp -vf "$laradock_path"/usvn/root$lsyncd_conf $lsyncd_conf
    fi
    [[ "$USER" == "root" ]] || $use_sudo sed -i "s/\/root\/docker/$HOME\/docker/g" $lsyncd_conf

    id_file="$HOME/.ssh/id_ed25519"
    if [ -f "$id_file" ]; then
        _msg time "found $id_file"
    else
        _msg time "new key, ssh-keygen"
        ssh-keygen -t ed25519 -f "$id_file" -N ''
    fi

    _msg time "config $lsyncd_conf"
    while read -rp "[$((++count))] Enter ssh host IP (enter q break): " ssh_host_ip; do
        [[ -z "$ssh_host_ip" || "$ssh_host_ip" == q ]] && break
        _msg time "ssh-copy-id -i $id_file root@$ssh_host_ip"
        ssh-copy-id -o StrictHostKeyChecking=no -i "$id_file" "root@$ssh_host_ip"
        _msg time "add $ssh_host_ip to $lsyncd_conf"
        line_num=$(grep -n '^targets' $lsyncd_conf | awk -F: '{print $1}')
        $use_sudo sed -i -e "$line_num a '$ssh_host_ip:$HOME/docker/html/'," $lsyncd_conf
        echo
    done
}

_install_acme() {
    if [ -d "$HOME/.acme.sh" ]; then
        _msg time "found $HOME/.acme.sh/ skip install acme.sh"
    else
        if ${IN_CHINA:-true}; then
            git clone --depth 1 https://gitee.com/neilpang/acme.sh.git
            cd acme.sh && ./acme.sh --install -m fly@laradock.com
        else
            curl https://get.acme.sh | bash -s email=fly@laradock.com
        fi
    fi
    echo "cd $HOME/.acme.sh && ./acme.sh --issue -d api.xxx.com -w $HOME/docker/html"
}

_upgrade_java() {
    $curl_opt $url_fly_cdn/spring.tar.gz | tar -C "$laradock_path"/ vzx
    $dco stop spring
    $dco rm -f
    $dco up -d spring
}

_upgrade_php() {
    $curl_opt $url_fly_cdn/tp.tar.gz | tar -C "$laradock_path"/../html/ vzx
}

_reset_laradock() {
    _msg step "reset laradock service"
    cd "$laradock_path" && $dco stop && $dco rm -f
    $use_sudo rm -rf "$laradock_path" "$laradock_path/../../laradock-data/mysql"
}

_usage() {
    cat <<EOF
Usage: $0 [parameters ...]

Parameters:
    -h, --help          Show this help message.
    -v, --version       Show version info.
    info                Get MySQL and Redis info.
    redis               Install Redis.
    mysql               Install MySQL.
    mysql-5.7           Install MySQL version 5.7.
    java                Install openjdk-8.
    java-17             Install openjdk-17.
    php                 Install php-fpm.
    php-8.2             Install php version 8.2.
    node                Install nodejs.
    node-19             Install nodejs version 19.
    nginx               Install nginx.
    mysql-cli           Exec into MySQL CLI.
    redis-cli           Exec into Redis CLI.
    lsync               Setup lsyncd.
    zsh                 Install zsh.
    gitlab              Install gitlab.
EOF
    exit 1
}

_set_args() {
    IN_CHINA=true
    php_ver=7.4
    java_ver=8
    mysql_ver=8.0

    args=()
    if [ "$#" -eq 0 ]; then
        _msg warn "not found arguments, with default args \"mysql redis php-fpm spring nginx\"."
        args+=(mysql redis php-fpm spring nginx)
        exec_check_docker=true
        exec_check_laradock=true
        exec_check_laradock_env=true
        exec_start_docker_service=true
        exec_pull_image=true
        return
    fi
    while [ "$#" -gt 0 ]; do
        case "${1}" in
        redis)
            args+=(redis)
            set_sysctl=true
            exec_group=1
            ;;
        mysql | mysql-[0-9]*)
            args+=(mysql)
            exec_group=1
            [[ "${1}" == mysql-[0-9]* ]] && mysql_ver=${1#mysql-}
            ;;
        java | jdk | spring | java-[0-9]* | jdk-[0-9]*)
            args+=(spring)
            exec_group=1
            [[ "${1}" == java-[0-9]* ]] && java_ver=${1#java-}
            [[ "${1}" == jdk-[0-9]* ]] && java_ver=${1#jdk-}
            ;;
        php | fpm | php-[0-9]*)
            args+=(php-fpm)
            exec_group=1
            [[ "${1}" == php-[0-9]* ]] && php_ver=${1#php-}
            ;;
        node | nodejs | node.js)
            args+=(nodejs)
            exec_group=1
            ;;
        nginx)
            args+=(nginx)
            exec_group=1
            ;;
        gitlab | git)
            args+=(gitlab)
            exec_group=1
            ;;
        svn | usvn)
            args+=(usvn)
            exec_group=1
            ;;
        upgrade)
            [[ "${args[*]}" == *php-fpm* ]] && exec_upgrade_php=true
            [[ "${args[*]}" == *spring* ]] && exec_upgrade_java=true
            ;;
        not-china | not-cn | ncn)
            IN_CHINA=false
            aliyun_mirror=false
            ;;
        install-docker-without-aliyun)
            aliyun_mirror=false
            exec_check_docker=true
            ;;
        install-zsh | zsh)
            exec_install_zsh=true
            exec_check_timezone=true
            ;;
        install-trzsz | trzsz)
            exec_install_trzsz=true
            exec_check_timezone=true
            ;;
        install-lsyncd | lsync | lsyncd)
            exec_install_lsyncd=true
            ;;
        install-wg | wg | wireguard)
            exec_install_wg=true
            ;;
        info)
            exec_env_info=true
            ;;
        mysql-cli)
            exec_mysql_cli=true
            ;;
        redis-cli)
            exec_redis_cli=true
            ;;
        test)
            exec_test_nginx=true
            exec_test_php=true
            ;;
        reset | clean | clear)
            exec_reset_laradock=true
            ;;
        acme)
            exec_install_acme=true
            ;;
        *)
            _usage
            ;;
        esac
        shift
    done
    if [ "${exec_group:-0}" -eq 1 ]; then
        exec_check_docker=true
        exec_check_laradock=true
        exec_check_laradock_env=true
        exec_start_docker_service=true
        exec_pull_image=true
    fi
}

main() {
    SECONDS=0

    _set_args "$@"

    set -e
    me_path="$(dirname "$(readlink -f "$0")")"
    me_name="$(basename "$0")"
    me_path_data="$me_path/../data"
    me_env="$me_path_data/$me_name.env"
    me_log="$me_path_data/$me_name.log"

    curl_opt='curl --connect-timeout 10 -fL'
    url_fly_cdn="http://oss.flyh6.com/d"

    if ${IN_CHINA:-true}; then
        url_laradock_git=https://gitee.com/xiagw/laradock.git
        url_laradock_raw=https://gitee.com/xiagw/laradock/raw/in-china
        url_deploy_raw=https://gitee.com/xiagw/deploy.sh/raw/main
        url_keys="$url_fly_cdn/xiagw.keys"
        url_get_docker="$url_fly_cdn/get-docker.sh"
        url_fzf="https://gitee.com/mirrors/fzf.git"
        url_ohmyzsh="https://gitee.com/mirrors/ohmyzsh.git"
    else
        url_laradock_git=https://github.com/xiagw/laradock.git
        url_laradock_raw=https://github.com/xiagw/laradock/raw/main
        url_deploy_raw=https://github.com/xiagw/deploy.sh/raw/main
        url_keys='https://github.com/xiagw.keys'
        url_get_docker="https://get.docker.com"
        url_fzf="https://github.com/junegunn/fzf.git"
        url_ohmyzsh="https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    fi
    echo "$me_env $url_laradock_raw $url_deploy_raw" >/dev/null

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

    if ${exec_install_acme:-false}; then
        _install_acme
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
    if ${exec_env_info:-false}; then
        _get_env_info
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

    ${exec_check_dependence:-true} && _check_dependence

    ${exec_install_trzsz:-false} && _install_trzsz
    if ${exec_install_zsh:-false}; then
        _install_zsh
        return
    fi
    if ${exec_install_lsyncd:-false}; then
        _install_lsyncd
        return
    fi
    if ${exec_install_wg:-false}; then
        _install_wg
        return
    fi

    ${exec_check_docker:-true} && _check_docker
    ## install docker, add normal user (not root) to group "docker", re-login
    ${need_logout:-false} && return

    if ${exec_reset_laradock:-false}; then
        _reset_laradock
        return
    fi

    ${exec_check_timezone:-false} && _check_timezone

    ${exec_check_laradock:-false} && _check_laradock

    ${exec_check_laradock_env:-false} && _check_laradock_env

    ${exec_pull_image:-false} && _pull_image

    ${exec_start_docker_service:-false} && _start_docker_service

    ${exec_test_nginx:-false} && _test_nginx

    ${exec_test_php:-false} && _test_php

    ${exec_test_java:-false} && _test_java
}

main "$@"
