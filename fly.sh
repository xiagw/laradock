#!/usr/bin/env bash
# shellcheck disable=SC1090

_set_system_conf() {
    ## redis-server 安装在服务器本机，非docker
    # grep -q 'transparent_hugepage/enabled' /etc/rc.local ||
    #     echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' | $use_sudo tee -a /etc/rc.local
    # $use_sudo source /etc/rc.local
    local sysctl_conf="/etc/sysctl.conf"
    local params=(
        "net.core.somaxconn = 1024"
        "vm.overcommit_memory = 1"
    )

    for param in "${params[@]}"; do
        if ! grep -q "${param%%=*}" "$sysctl_conf"; then
            echo "$param" | ${use_sudo-} tee -a "$sysctl_conf" >/dev/null
        fi
    done

    $use_sudo sysctl -p
}

_check_dependence() {
    _check_sudo
    _check_distribution
    _msg step "Checking commands: curl, git, binutils."
    _check_cmd install curl git strings

    _msg time "Checking SSH configuration."
    dot_ssh="$HOME/.ssh"
    ssh_auth="$dot_ssh/authorized_keys"
    [ -d "$dot_ssh" ] || mkdir -m 700 "$dot_ssh"

    update_ssh_keys() {
        local url="$1"
        $g_curl_opt -sS "$url" | grep -vE '^#|^$|^\s+$' |
            while read -r line; do
                key=$(echo "$line" | awk '{print $2}')
                grep -q "$key" "$ssh_auth" || echo "$line" >>"$ssh_auth"
            done
    }

    update_ssh_keys "$g_url_keys"
    ${arg_insert_key:-false} && update_ssh_keys "$g_url_fly_keys"

    chmod 600 "$ssh_auth"

    ${set_sysctl:-false} && _set_system_conf

    _msg time "Dependency check completed."
}

_check_docker_compose() {
    dco="docker compose"
    if $dco version; then
        _msg green "$dco ready."
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
    _msg step "Check docker and docker compose"
    if _check_cmd docker; then
        _check_docker_compose
        _msg time "docker is already installed."
        return
    fi

    # Handle OpenEuler distribution
    if grep -q -E '^ID=.*openEuler.*' /etc/os-release; then
        $use_sudo curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
        $use_sudo sed -i 's#https://download.docker.com#https://mirrors.tuna.tsinghua.edu.cn/docker-ce#' /etc/yum.repos.d/docker-ce.repo
        $use_sudo sed -i "s#\$releasever#7#g" /etc/yum.repos.d/docker-ce.repo
        ${cmd_pkg-} install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        # Handle Aliyun Linux
        if grep -q -E '^ID=.*alinux.*' /etc/os-release; then
            $use_sudo sed -i -e '/^ID=/s/ID=.*/ID=centos/' /etc/os-release
            fake_os=true
        fi
    fi

    # Install Docker using Aliyun mirror
    local url="$g_url_get_docker"
    if ${aliyun_mirror:-true}; then
        echo "${version_id-}"
        if [[ "${version_id%%.*}" -ne 7 ]]; then
            url="$g_url_get_docker2"
        fi
    fi
    # shellcheck disable=2046
    $g_curl_opt "$url" | $use_sudo bash $(${aliyun_mirror:-true} && echo '-s - --mirror Aliyun')

    # Add user to docker group if not root
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

    # Add other users to docker group
    for u in ubuntu centos ops; do
        [[ "$USER" != "$u" ]] && id "$u" &>/dev/null && $use_sudo usermod -aG docker "$u"
    done

    # Revert Aliyun Linux fake Centos
    ${fake_os:-false} && $use_sudo sed -i -e '/^ID=/s/centos/alinux/' /etc/os-release

    # Enable and start Docker
    $use_sudo systemctl enable --now docker
    _check_docker_compose
}

_check_laradock() {
    _msg step "Check laradock"
    if [[ -d "$g_laradock_path" && -d "$g_laradock_path/.git" ]]; then
        _msg time "$g_laradock_path exist, git pull."
        (cd "$g_laradock_path" && git pull)
        return 0
    fi
    _msg step "Clone laradock to $g_laradock_path/"
    mkdir -p "$g_laradock_path"
    git clone -b in-china --depth 1 $g_url_laradock_git "$g_laradock_path"

    ## jdk image, uid is 1000.(see spring/Dockerfile)
    if [[ "$(stat -c %u "$g_laradock_path/spring")" != 1000 ]]; then
        if $use_sudo chown 1000:1000 "$g_laradock_path/spring"; then
            _msg time "OK: chown 1000:1000 $g_laradock_path/spring"
        else
            _msg red "FAIL: chown 1000:1000 $g_laradock_path/spring"
        fi
    fi
}

_check_laradock_env() {
    # Skip if env file exists and force update not enabled
    if [[ -f "$g_laradock_env" && "${force_update_env:-0}" -eq 0 ]]; then
        return 0
    fi
    _msg step "Set laradock .env"

    # Get docker host IP
    docker_host_ip=$(/sbin/ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)

    _msg time "copy .env.example to .env, and set random password"
    cp -vf "$g_laradock_env".example "$g_laradock_env"

    # Update .env file with new values
    sed -i \
        -e "/^MYSQL_PASSWORD=/s/=.*/=$(_get_random_password)/" \
        -e "/^MYSQL_ROOT_PASSWORD=/s/=.*/=$(_get_random_password)/" \
        -e "/^REDIS_PASSWORD=/s/=.*/=$(_get_random_password)/" \
        -e "/^PHPREDISADMIN_PASS=/s/=.*/=$(_get_random_password)/" \
        -e "/^GITLAB_ROOT_PASSWORD=/s/=.*/=$(_get_random_password)/" \
        -e "/^MYSQL_VERSION=/s/=.*/=${g_mysql_ver}/" \
        -e "/^PHP_VERSION=/s/=.*/=${g_php_ver}/" \
        -e "/^JDK_VERSION=/s/=.*/=${g_java_ver}/" \
        -e "/^NODE_VERSION=/s/=.*/=${g_node_ver}/" \
        -e "/^CHANGE_SOURCE=/s/false/$IN_CHINA/" \
        -e "/^DOCKER_HOST_IP=/s/=.*/=$docker_host_ip/" \
        -e "/^GITLAB_HOST_SSH_IP=/s/=.*/=$docker_host_ip/" \
        "$g_laradock_env"

    # Update listen ports
    for p in 80 443 3306 6379; do
        local listen_port=$p
        while ss -lntu4 | grep "LISTEN.*:$listen_port\ "; do
            _msg red "already LISTEN port: $listen_port ."
            listen_port=$((listen_port + 2))
            _msg yellow "try next port: $listen_port ..."
        done
        case $p in
        80) sed -i -e "/^NGINX_HOST_HTTP_PORT=/s/=.*/=$listen_port/" "$g_laradock_env" ;;
        443) sed -i -e "/^NGINX_HOST_HTTPS_PORT=/s/=.*/=$listen_port/" "$g_laradock_env" ;;
        3306) sed -i -e "/^MYSQL_PORT=/s/=.*/=$listen_port/" "$g_laradock_env" ;;
        6379) sed -i -e "/^REDIS_PORT=/s/=.*/=$listen_port/" "$g_laradock_env" ;;
        esac
    done

    ## set SHELL_OH_MY_ZSH=true
    echo "$SHELL" | grep -q zsh && sed -i -e "/SHELL_OH_MY_ZSH=/s/false/true/" "$g_laradock_env" || return 0
}
_reload_nginx() {
    pushd "$g_laradock_path" || exit 1
    local max_attempts=5
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if $dco exec -T nginx nginx -t; then
            $dco exec -T nginx nginx -s reload
            break
        else
            _msg time "[$((attempt * 2))] reload nginx err."
        fi
        ((attempt++))
        sleep 2
    done
    popd || return
}
_set_nginx_php() {
    ## setup php upstream
    sed -i 's/127\.0\.0\.1/php-fpm/g' "$g_laradock_path/nginx/sites/router.inc"
}

_set_env_php_ver() {
    sed -i \
        -e "/^PHP_VERSION=/s/=.*/=${g_php_ver}/" \
        -e "/CHANGE_SOURCE=/s/false/$IN_CHINA/" "$g_laradock_env"
}

_set_env_node_ver() {
    sed -i "/^NODE_VERSION=/s/=.*/=${g_node_ver}/" "$g_laradock_env"
    source <(grep '^NODE_VERSION=' "$g_laradock_env")
}

_set_env_java_ver() {
    sed -i "/^JDK_VERSION=/s/=.*/=${g_java_ver}/" "$g_laradock_env"
    source <(grep '^JDK_VERSION=' "$g_laradock_env")
}

_set_file_mode() {
    local d line
    for d in "$g_laradock_path"/../*/; do
        [[ "$d" == *laradock/ ]] && continue
        while IFS= read -r line; do
            case "$line" in
            *config/app.php)
                # Set app_debug to false in app.php
                grep -q 'app_debug.*true' "$line" && $use_sudo sed -i -e '/app_debug/s/true/false/' "$line"
                ;;
            *config/log.php)
                # Add 'warning' to log levels in log.php
                grep -q "'level'.*\[\]\," "$line" && $use_sudo sed -i -e "/'level'/s/\[/\['warning'/" "$line"
                ;;
            esac
        done < <(find "$d")
    done
}

_install_zsh() {
    _msg step "Install oh my zsh"

    _check_cmd install zsh

    ## fzf
    if [[ "${lsb_dist-}" =~ (alinux|centos|openEuler) ]]; then
        if [[ -d "$HOME"/.fzf ]]; then
            _msg warn "Found $HOME/.fzf, skip git clone fzf."
        else
            git clone --depth 1 "$g_url_fzf" "$HOME"/.fzf
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
            git clone --depth 1 "$g_url_ohmyzsh" "$HOME"/.oh-my-zsh
        else
            bash -c "$($g_curl_opt "$g_url_ohmyzsh")"
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
        _msg warn "skip trzsz install"
    else
        _msg step "Install trzsz"
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

_install_lsyncd() {
    _msg step "Install lsyncd"
    _check_cmd install lsyncd

    lsyncd_conf=/etc/lsyncd/lsyncd.conf.lua
    [ -d /etc/lsyncd/ ] || $use_sudo mkdir /etc/lsyncd
    if [ -f $lsyncd_conf ]; then
        _msg time "found $lsyncd_conf"
    else
        _msg time "new lsyncd.conf.lua"
        $use_sudo cp -vf "$g_laradock_path"/usvn/root$lsyncd_conf $lsyncd_conf
    fi
    [[ "$USER" == "root" ]] || $use_sudo sed -i "s@/root/docker@$HOME/docker@g" $lsyncd_conf

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
        $use_sudo sed -i -e "/^htmlhosts/ a '$ssh_host_ip:$g_laradock_path/../html/'," $lsyncd_conf
        $use_sudo sed -i -e "/^nginxhosts/ a '$ssh_host_ip:$g_laradock_path/nginx/'," $lsyncd_conf
        echo
    done
}

_install_acme() {
    _msg step "Install acme.sh."
    local acme_home="$HOME/.acme.sh"
    local key="$g_laradock_home/nginx/sites/ssl/default.key"
    local pem="$g_laradock_home/nginx/sites/ssl/default.pem"
    local html="$HOME"/docker/html
    if [ -f "$acme_home/acme.sh" ]; then
        _msg time "found $acme_home/acme.sh, skip install acme.sh"
    else
        if ${IN_CHINA:-true}; then
            git clone --depth 1 https://gitee.com/neilpang/acme.sh.git
            cd acme.sh && ./acme.sh --install -m fly@laradock.com
        else
            curl https://get.acme.sh | bash -s email=fly@laradock.com
        fi
    fi
    domain="${1}"
    _msg time "your domain is: ${domain:-api.xxx.com}"
    case "$domain" in
    *.*.*)
        cd "$acme_home" || return 1
        ./acme.sh --issue -w "$html" -d "$domain"
        ./acme.sh --install-cert --key-file "$key" --fullchain-file "$pem" -d "$domain"
        ;;
    *)
        echo
        echo "Single host domain:"
        echo "  cd $acme_home && ./acme.sh --issue -w $html -d ${domain:-api.xxx.com}"
        echo "Wildcard domain:"
        echo "  cd $acme_home && ./acme.sh --issue -w $html -d ${domain:-api.xxx.com} -d '${domain:-*.xxx.com}' "
        echo "DNS API: [https://github.com/acmesh-official/acme.sh/wiki/dnsapi]"
        echo "  cd $acme_home && ./acme.sh --issue --dns dns_cf -d ${domain:-api.xxx.com} -d '${domain:-*.xxx.com}' "
        echo "Deploy cert"
        echo "  cd $acme_home && ./acme.sh --install-cert --key-file $key --fullchain-file $pem -d ${domain:-api.xxx.com}"
        ;;
    esac
    # openssl x509 -noout -text -in xxx.pem
    # openssl x509 -noout -dates -in xxx.pem
}

# 递增等待显示函数，使用 '#' 符号
_incremental_wait() {
    local counter=0
    local should_exit=0

    # 定义信号处理函数
    trap 'should_exit=1' USR1 INT TERM

    while [ $should_exit -eq 0 ]; do
        printf "#"
        ((counter++))
        sleep 1
    done

    # 在退出时打印换行，以便下一行输出正常显示
    echo " Total duration: $counter seconds"
    return $counter
}

_start_docker_service() {
    if [ "${#args[@]}" -gt 0 ]; then
        _msg step "Start docker service automatically..."
    else
        _msg warn "no arguments for docker service"
        return
    fi
    cd "$g_laradock_path" || exit 1
    $dco up -d "${args[@]}"
    ## wait startup
    for arg in "${args[@]}"; do
        _incremental_wait &
        pid=$!
        until ((i > 8)) || $dco ps | grep -q "$arg"; do
            ((i++))
            sleep 1
        done
    done
}

_pull_image() {
    _msg step "Check docker image..."
    local image_repo=registry.cn-hangzhou.aliyuncs.com/flyh5/flyh5
    local docker_ver
    local image_prefix
    docker_ver="$(docker --version | awk '{gsub(/[,]/,""); print int($3)}')"

    [ "$docker_ver" -le 19 ] && image_prefix="laradock_" || image_prefix="laradock-"
    cmd_pull="docker pull -q"
    cmd_tag="docker tag"

    for i in "${args[@]}"; do
        _msg time "docker pull image $i ..."
        case $i in
        nginx)
            arg_test_nginx=true
            _incremental_wait &
            pid=$!
            $cmd_pull "$image_repo:laradock-nginx" >/dev/null
            $cmd_tag "$image_repo:laradock-nginx" "${image_prefix}nginx"
            ;;
        redis)
            _incremental_wait &
            pid=$!
            $cmd_pull "$image_repo:laradock-redis" >/dev/null
            $cmd_tag "$image_repo:laradock-redis" "${image_prefix}redis"
            ;;
        mysql)
            source <(grep '^MYSQL_VERSION=' "$g_laradock_env")
            _incremental_wait &
            pid=$!
            $cmd_pull "$image_repo:laradock-mysql-${MYSQL_VERSION}" >/dev/null
            $cmd_tag "$image_repo:laradock-mysql-${MYSQL_VERSION}" "${image_prefix}mysql"
            ## mysqlbak
            if [ ! -d "$g_laradock_path"/../../laradock-data/mysqlbak ]; then
                $use_sudo mkdir -p "$g_laradock_path"/../../laradock-data/mysqlbak
            fi
            $use_sudo chown 1000:1000 "$g_laradock_path"/../../laradock-data/mysqlbak
            $cmd_pull "$image_repo:laradock-mysqlbak" >/dev/null
            $cmd_tag "$image_repo:laradock-mysqlbak" "${image_prefix}mysqlbak"
            ;;
        spring)
            _set_env_java_ver
            arg_test_java=true
            _incremental_wait &
            pid=$!
            $cmd_pull "$image_repo:laradock-spring-${g_java_ver}" >/dev/null
            $cmd_tag "$image_repo:laradock-spring-${g_java_ver}" "${image_prefix}spring"
            ;;
        nodejs)
            _set_env_node_ver
            _incremental_wait &
            pid=$!
            $cmd_pull "$image_repo:laradock-nodejs-${g_node_ver}" >/dev/null
            $cmd_tag "$image_repo:laradock-nodejs-${g_node_ver}" "${image_prefix}nodejs"
            ;;
        php*)
            _set_env_php_ver
            arg_test_php=true
            _incremental_wait &
            pid=$!
            $cmd_pull "$image_repo:laradock-php-fpm-${g_php_ver}" >/dev/null
            $cmd_tag "$image_repo:laradock-php-fpm-${g_php_ver}" "${image_prefix}php-fpm"
            ;;
        esac
    done
    ## remove image
    docker image ls | grep "$image_repo" | awk '{print $1":"$2}' | xargs docker rmi -f >/dev/null
}

_test_nginx() {
    _reload_nginx
    source <(grep 'NGINX_HOST_HTTP_PORT' "$g_laradock_env")
    $dco stop nginx && $dco up -d nginx
    [ -f "$g_laradock_path/../html/favicon.ico" ] || $g_curl_opt -s -o "$g_laradock_path/../html/favicon.ico" $g_url_fly_ico
    _msg time "test nginx $1 ..."
    for i in {1..5}; do
        if $g_curl_opt "http://localhost:${NGINX_HOST_HTTP_PORT}/${1}"; then
            break
        else
            _msg time "test nginx error...[$((i * 2))]"
            sleep 2
        fi
    done
}

_test_php() {
    path_nginx_root="$g_laradock_path/../html"
    $use_sudo chown "$USER:$USER" "$path_nginx_root"
    if [[ ! -f "$path_nginx_root/test.php" ]]; then
        _msg time "Create test.php"
        $use_sudo cp -avf "$g_laradock_path/php-fpm/test.php" "$path_nginx_root/test.php"
        source "$g_laradock_env" 2>/dev/null
        sed -i \
            -e "s/ENV_REDIS_PASSWORD/$REDIS_PASSWORD/" \
            -e "s/ENV_MYSQL_USER/$MYSQL_USER/" \
            -e "s/ENV_MYSQL_PASSWORD/$MYSQL_PASSWORD/" \
            "$path_nginx_root/test.php"
    fi
    _test_nginx "test.php"
}

_test_java() {
    _msg time "check spring..."
    if $dco ps | grep "spring.*Up"; then
        _msg green "container spring is up"
    else
        _msg red "container spring is down"
    fi
}

_get_env_info() {
    set +e
    echo "####  代码内写标准端口 mysql:3306 / redis:6379"
    echo "####  此处显示端口只用于SSH端口转发映射(可能不同于标准端口)"
    grep -E '^REDIS_' "$g_laradock_env" | sed -n '1,3p'
    echo
    grep -E '^DB_HOST|^MYSQL_' "$g_laradock_env" | grep -vE 'MYSQL_ROOT_PASSWORD|MYSQL_ENTRYPOINT_INITDB|MYSQL_SLAVE_ID'
    echo
    grep -E '^JDK_IMAGE|^JDK_VERSION' "$g_laradock_env"
    echo
    grep -E '^PHP_VERSION' "$g_laradock_env"
    echo
    grep -E '^NODE_VERSION' "$g_laradock_env"
}

_mysql_cli() {
    cd "$g_laradock_path"
    source <(grep -E '^MYSQL_DATABASE=|^MYSQL_USER=|^MYSQL_PASSWORD=' "$g_laradock_env")
    docker compose exec mysql bash -c "LANG=C.UTF-8 MYSQL_PWD=$MYSQL_PASSWORD mysql -u $MYSQL_USER $MYSQL_DATABASE"
}

_redis_cli() {
    cd "$g_laradock_path"
    source <(grep '^REDIS_PASSWORD=' "$g_laradock_env")
    docker compose exec redis bash -c "redis-cli --no-auth-warning -a $REDIS_PASSWORD"
}

_upgrade_java() {
    $g_curl_opt $g_url_fly_cdn/spring.tar.gz | tar -C "$g_laradock_path"/ vzx
    $dco stop spring
    $dco rm -f
    $dco up -d spring
}

_upgrade_php() {
    $g_curl_opt $g_url_fly_cdn/tp.tar.gz | tar -C "$g_laradock_path"/../html/ vzx
}

_reset_laradock() {
    _msg step "Reset laradock service"
    cd "$g_laradock_path" && $dco stop && $dco rm -f
    $use_sudo rm -rf "$g_laradock_path" "$g_laradock_path/../../laradock-data/mysql"
}

_refresh_cdn() {
    set +e
    local oss_name="${1}"
    local obj_path="${2}"
    local region="${3:-cn-hangzhou}"
    local temp_file="/tmp/cdn.txt"
    local get_result local_saved object_type

    while true; do
        get_result=$(aliyun oss cat "oss://$oss_name/cdn.txt" 2>/dev/null | head -n1)
        local_saved=$(cat "$temp_file" 2>/dev/null)
        if [[ "$get_result" != "$local_saved" ]]; then
            echo "get_result: $get_result, local_saved: $local_saved"
            object_type=$([ "${obj_path: -1}" = "/" ] && echo "Directory" || echo "File")
            aliyun cdn RefreshObjectCaches --region "$region" --ObjectType "$object_type" --ObjectPath "${obj_path}"
            echo "refresh cdn $region ${obj_path}"
            echo "$get_result" >"$temp_file"
        fi
        sleep 10
    done
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
    lsync               Install and setup lsyncd.
    zsh                 Install zsh.
    gitlab              Install gitlab.
    acme                Install acme.sh.
    cdn                 Refresh CDN: [cdn oss-name domain.com/ cn-hangzhou]
EOF
    exit 1
}

_parse_args() {
    IN_CHINA=true
    g_php_ver=7.4
    g_java_ver=8
    g_mysql_ver=8.0
    g_node_ver=18

    args=()
    if [ "$#" -eq 0 ] || { [ "$#" -eq 1 ] && [ "$1" = key ]; }; then
        echo -e "\033[0;33mnot found any arguments, with default args \"redis mysql php-fpm spring nginx\".\033[0m"
        args+=(redis mysql php-fpm spring nginx)
        arg_group=1
    fi
    while [ "$#" -gt 0 ]; do
        case "${1}" in
        redis)
            args+=(redis)
            set_sysctl=true
            arg_group=1
            ;;
        mysql | mysql-[0-9]*)
            args+=(mysql)
            arg_group=1
            [[ "${1}" == mysql-[0-9]* ]] && g_mysql_ver=${1#mysql-}
            ;;
        java | jdk | spring | java-[0-9]* | jdk-[0-9]* | spring-[0-9]*)
            args+=(spring)
            arg_group=1
            [[ "${1}" == java-[0-9]* ]] && g_java_ver=${1#java-}
            [[ "${1}" == jdk-[0-9]* ]] && g_java_ver=${1#jdk-}
            ;;
        php | fpm | php-[0-9]* | php-fpm-[0-9]*)
            args+=(php-fpm)
            arg_group=1
            [[ "${1}" == php-[0-9]* ]] && g_php_ver=${1#php-}
            [[ "${1}" == php-fpm-[0-9]* ]] && g_php_ver=${1#php-fpm-}
            ;;
        node | nodejs | node-[0-9]* | nodejs-[0-9]*)
            args+=(nodejs)
            [[ "${1}" == node-[0-9]* ]] && g_node_ver=${1#node-}
            [[ "${1}" == nodejs-[0-9]* ]] && g_node_ver=${1#nodejs-}
            arg_group=1
            ;;
        nginx)
            args+=(nginx)
            arg_group=1
            ;;
        gitlab | git)
            args+=(gitlab)
            arg_group=1
            ;;
        svn | usvn)
            args+=(usvn)
            arg_group=1
            ;;
        upgrade)
            [[ "${args[*]}" == *php-fpm* ]] && arg_upgrade_php=true
            [[ "${args[*]}" == *spring* ]] && arg_upgrade_java=true
            ;;
        not-china | not-cn | ncn)
            IN_CHINA=false
            aliyun_mirror=false
            ;;
        install-docker-without-aliyun)
            aliyun_mirror=false
            arg_check_docker=true
            ;;
        install-zsh | zsh)
            arg_install_zsh=true
            arg_check_timezone=true
            ;;
        install-acme | acme)
            arg_install_acme=true
            arg_domain="$2"
            [ -z "$2" ] || shift
            ;;
        install-trzsz | trzsz)
            arg_install_trzsz=true
            arg_check_timezone=true
            ;;
        install-lsyncd | lsync | lsyncd)
            arg_install_lsyncd=true
            ;;
        install-wg | wg | wireguard)
            arg_install_wg=true
            ;;
        info)
            arg_env_info=true
            ;;
        mysql-cli)
            arg_mysql_cli=true
            ;;
        redis-cli)
            arg_redis_cli=true
            ;;
        test)
            arg_test_nginx=true
            arg_test_php=true
            ;;
        reset | clean | clear)
            arg_reset_laradock=true
            ;;
        key)
            arg_insert_key=true
            ;;
        cdn | refresh)
            shift
            _refresh_cdn "$@"
            return
            ;;
        *)
            _usage
            ;;
        esac
        shift
    done
    # unique_array=($(printf "%s\n" "${args[@]}" | awk '!seen[$0]++'))
    if [ "${arg_group:-0}" -eq 1 ]; then
        arg_check_docker=true
        arg_check_laradock=true
        arg_check_laradock_env=true
        arg_start_docker_service=true
        arg_pull_image=true
    fi
}

_include_sh() {
    include_sh="$g_me_path/include.sh"
    if [ ! -f "$include_sh" ]; then
        include_sh='/tmp/include.sh'
        include_url="$g_deploy_raw/bin/include.sh"
        [ -f "$include_sh" ] || curl -fsSL "$include_url" >"$include_sh"
    fi
    . "$include_sh"
}

main() {
    SECONDS=0

    _parse_args "$@"

    set -e
    ## global variables g_* / 全局变量
    g_me_path="$(dirname "$(readlink -f "$0")")"
    g_me_name="$(basename "$0")"
    g_me_env="$g_me_path/${g_me_name}.env"
    g_me_log="$g_me_path/${g_me_name}.log"

    g_curl_opt='curl --connect-timeout 10 -fL'
    g_url_fly_cdn="http://oss.flyh6.com/d"
    g_url_fly_keys="$g_url_fly_cdn/flyh6.keys"
    g_url_fly_ico="$g_url_fly_cdn/flyh6.ico"

    if ${IN_CHINA:-true}; then
        g_url_laradock_git=https://gitee.com/xiagw/laradock.git
        g_url_laradock_raw=https://gitee.com/xiagw/laradock/raw/in-china
        g_deploy_raw=https://gitee.com/xiagw/deploy.sh/raw/main
        g_url_keys="$g_url_fly_cdn/xiagw.keys"
        g_url_get_docker="$g_url_fly_cdn/get-docker.sh"
        g_url_get_docker2="$g_url_fly_cdn/get-docker2.sh"
        g_url_fzf="https://gitee.com/mirrors/fzf.git"
        g_url_ohmyzsh="https://gitee.com/mirrors/ohmyzsh.git"
    else
        g_url_laradock_git=https://github.com/xiagw/laradock.git
        g_url_laradock_raw=https://github.com/xiagw/laradock/raw/main
        g_deploy_raw=https://github.com/xiagw/deploy.sh/raw/main
        g_url_keys='https://github.com/xiagw.keys'
        g_url_get_docker="https://get.docker.com"
        g_url_fzf="https://github.com/junegunn/fzf.git"
        g_url_ohmyzsh="https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    fi
    echo "$g_me_env $g_me_log $g_url_laradock_raw" >/dev/null

    _include_sh

    g_laradock_home="$HOME"/docker/laradock
    g_laradock_current="$g_me_path"
    if [[ -f "$g_laradock_current/fly.sh" && -f "$g_laradock_current/.env.example" ]]; then
        ## 从本机已安装目录执行 fly.sh
        g_laradock_path="$g_laradock_current"
    elif [[ -f "$g_laradock_home/fly.sh" && -f "$g_laradock_home/.env.example" ]]; then
        g_laradock_path=$g_laradock_home
    else
        ## 从远程执行 fly.sh , curl "remote_url" | bash -s args
        g_laradock_path="$g_laradock_current"/docker/laradock
    fi

    g_laradock_env="$g_laradock_path"/.env

    if ${arg_install_acme:-false}; then
        _install_acme "$arg_domain"
        return
    fi
    if ${arg_mysql_cli:-false}; then
        _mysql_cli
        return
    fi
    if ${arg_redis_cli:-false}; then
        _redis_cli
        return
    fi
    if ${arg_env_info:-false}; then
        _get_env_info
        return
    fi
    if ${arg_upgrade_java:-false}; then
        _upgrade_java
        return
    fi
    if ${arg_upgrade_php:-false}; then
        _upgrade_php
        return
    fi

    ${arg_check_dependence:-true} && _check_dependence

    ${arg_install_trzsz:-false} && _install_trzsz
    if ${arg_install_zsh:-false}; then
        _install_zsh
        return
    fi
    if ${arg_install_lsyncd:-false}; then
        _install_lsyncd
        return
    fi
    if ${arg_install_wg:-false}; then
        _install_wg
        return
    fi

    ${arg_check_docker:-true} && _check_docker
    ## install docker, add normal user (not root) to group "docker", re-login
    ${need_logout:-false} && return

    if ${arg_reset_laradock:-false}; then
        _reset_laradock
        return
    fi

    ${arg_check_timezone:-false} && _check_timezone

    ${arg_check_laradock:-false} && _check_laradock

    ${arg_check_laradock_env:-false} && _check_laradock_env

    ${arg_pull_image:-false} && _pull_image

    ${arg_start_docker_service:-false} && _start_docker_service

    ${arg_test_nginx:-false} && _test_nginx

    ${arg_test_php:-false} && _test_php

    ${arg_test_java:-false} && _test_java
}

main "$@"
