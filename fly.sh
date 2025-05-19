#!/usr/bin/env bash
# shellcheck disable=SC1090

_set_system_conf() {
    ## redis-server 安装在服务器本机时告警修复，（非docker）
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

check_dependence() {
    # 1. 基本命令检查
    _check_distribution
    _msg step "Checking commands: curl, git, binutils."
    _check_cmd install curl git strings

    # 2. SSH 配置 (不需要 sudo)
    _msg time "Checking SSH configuration."
    dot_ssh="$HOME/.ssh"
    auth_keys="$dot_ssh/authorized_keys"
    [ -d "$dot_ssh" ] || mkdir -m 700 "$dot_ssh"

    update_ssh_keys() {
        local url="$1"
        $g_curl_opt -sS "$url" | grep -vE '^#|^$|^\s+$' |
            while read -r line; do
                key=$(echo "$line" | awk '{print $2}')
                grep -q "$key" "$auth_keys" 2>/dev/null || echo "$line" >>"$auth_keys"
            done
    }

    update_ssh_keys "$g_url_keys"
    ${arg_insert_key:-false} && update_ssh_keys "$g_url_keys_fly"
    chmod 600 "$auth_keys"

    # 3. 需要 sudo 的系统配置操作
    _check_sudo # 移到这里，因为后面的操作都需要 sudo

    # 系统配置更改
    ${set_sysctl:-false} && _set_system_conf

    # Sudoers 配置
    if ! _check_root; then
        echo "$USER ALL=(ALL) NOPASSWD: ALL" | $use_sudo tee /etc/sudoers.d/"$USER" >/dev/null
    fi

    # IPv6 配置
    $use_sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
    $use_sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
    $use_sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1

    _msg time "Dependency check completed."
}

check_docker_compose() {
    dco="docker compose"
    if $dco version 2>/dev/null; then
        _msg green "$dco ready."
    else
        dco="docker-compose"
        if _check_cmd $dco; then
            dco_ver=$($dco -v | awk '{gsub(/[,\.]/,""); print int($3)}')
            if [[ "$dco_ver" -lt 1190 ]]; then
                _msg warn "$dco version is too old."
            fi
        fi
    fi
}

_force_user_logout() {
    local user="$1"
    _msg warn "Forcing logout for user: $user"

    # 1. Try loginctl first (systemd)
    if command -v loginctl >/dev/null 2>&1; then
        $use_sudo loginctl terminate-user "$user"
        return
    fi

    # 2. Fallback: find and terminate user sessions using pgrep
    $use_sudo pgrep -f "sshd:.*$user@pts" |
        while read -r pid; do
            _msg warn "Terminating session pid: $pid"
            # 先发送 TERM 信号
            $use_sudo kill -TERM "$pid"
            sleep 2
            # 如果进程还在，再用 HUP 信号
            $use_sudo kill -HUP "$pid"
        done
}

add_to_docker_group() {
    # Skip for root user or if user already in docker group
    if _check_root || groups "$USER" | grep -q docker; then
        return 0
    fi

    # Add other users to docker group
    for u in ubuntu centos ops; do
        if [[ "$USER" != "$u" ]] && id "$u" &>/dev/null; then
            $use_sudo usermod -aG docker "$u"
            _force_user_logout "$u"
        fi
    done

    # Add user to docker group
    _msg time "Add user \"$USER\" to group docker."
    $use_sudo usermod -aG docker "$USER"
    echo '############################################'
    _msg red "!!!! Adding user to docker group requires logout !!!!"
    _msg yellow "System will force logout in 5 seconds..."
    echo '############################################'
    sleep 5
    _force_user_logout "$USER"
    need_logout=true
    exit 0
}

check_docker() {
    _msg step "Check docker and docker-compose"
    if _check_cmd docker; then
        check_docker_compose
        _msg time "docker is already installed."
        $use_sudo systemctl enable --now docker.service 2>/dev/null || true
        $use_sudo /lib/systemd/systemd-sysv-install enable docker.service 2>/dev/null || true
        add_to_docker_group
        return 0
    fi

    # Handle OpenEuler distribution
    local os_id fake_os cmd_pkg2
    os_id="$(awk -F'=' '/^ID=.*/ {print $2}' /etc/os-release | sed 's/"//g' | head -n1)"
    case "$os_id" in
    *openEuler*)
        $use_sudo curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
        $use_sudo sed -i 's#https://download.docker.com#https://mirrors.tuna.tsinghua.edu.cn/docker-ce#' /etc/yum.repos.d/docker-ce.repo
        $use_sudo sed -i "s#\$releasever#7#g" /etc/yum.repos.d/docker-ce.repo
        ${cmd_pkg-} install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
    *kylin | *kylin*)
        cmd_pkg2="$(command -v dnf || command -v yum)"
        $cmd_pkg2 install -y docker-engine || {
            echo "Unsupport install package docker-engine"
            return 1
        }
        ;;
    tencentos | opencloudos)
        cmd_pkg2="$(command -v dnf || command -v yum)"
        $cmd_pkg2 install -y docker-ce || {
            echo "Unsupport install package docker-ce"
            return 1
        }
        ;;
    *alinux | *alinux*)
        # Handle Aliyun Linux
        $use_sudo sed -i -e '/^ID=/s/ID=.*/ID=centos/' /etc/os-release
        fake_os=true
        ;;
    esac

    # Install Docker using Aliyun mirror
    local url="$g_url_get_docker" cmd_arg
    if ${aliyun_mirror:-true}; then
        cmd_arg='-s - --mirror Aliyun'
        echo "${version_id-}"
        if [[ "${version_id%%.*}" -ne 7 ]]; then
            url="$g_url_get_docker2"
        fi
    fi
    if [ -z "${cmd_pkg2}" ]; then
        # shellcheck disable=2046,2086
        $g_curl_opt "$url" | $use_sudo bash ${cmd_arg}
    fi

    add_to_docker_group || true

    # Revert Aliyun Linux fake Centos
    ${fake_os:-false} && $use_sudo sed -i -e '/^ID=/s/centos/alinux/' /etc/os-release

    # Enable and start Docker
    $use_sudo systemctl enable --now docker 2>/dev/null || true
    $use_sudo /lib/systemd/systemd-sysv-install enable docker 2>/dev/null || true
    check_docker_compose
}

check_laradock() {
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

check_laradock_env() {
    # Skip if env file exists and force update not enabled
    if [[ -f "$g_laradock_env" ]]; then
        # Update .env file with new values
        sed -i \
            -e "/^MYSQL_VERSION=/s/=.*/=${g_mysql_ver}/" \
            -e "/^PHP_VERSION=/s/=.*/=${g_php_ver}/" \
            -e "/^JDK_VERSION=/s/=.*/=${g_java_ver}/" \
            -e "/^NODE_VERSION=/s/=.*/=${g_node_ver}/" \
            "$g_laradock_env"
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
    cd "$g_laradock_path" || return 1
    for ((i = 1; i <= 5; i++)); do
        if $dco exec -T nginx nginx -t && $dco exec -T nginx nginx -s reload; then
            break
        fi
        _msg time "nginx reload failed, attempt $i/5"
        sleep 2
    done
    cd - >/dev/null || return 1
}

_set_file_mode() {
    # 使用更精确的路径排除
    local parent
    parent="$(dirname "$g_laradock_path")"
    find "$parent"/* -type f \( -name "app.php" -o -name "log.php" \) -not -path "$parent/laradock/*" |
        while read -r file; do
            case "$file" in
            */config/app.php) $use_sudo sed -i '/app_debug/s/true/false/' "$file" ;;
            */config/log.php) $use_sudo sed -i "/'level'/s/\[\]/\['warning']/" "$file" ;;
            esac
        done
}

_install_zsh() {
    _msg step "Install zsh"
    ${IN_CHINA:-true} && _set_mirror os
    _check_cmd install zsh

    # Install and configure fzf
    _msg time "Install fzf"
    if [[ "${lsb_dist-}" =~ (alinux|centos|openEuler|kylin) ]]; then
        [ -d "$HOME/.fzf" ] || git clone --depth 1 "$g_url_fzf" "$HOME/.fzf"
        local v
        v=$(awk -F'=' '/^version/ {print $2}' "$HOME/.fzf/install" | head -n1)
        sed -i "s|url=http.*|url=$g_url_fly_cdn/fzf-${v:-0.61.3}-linux_amd64.tar.gz|" "$HOME/.fzf/install"
        "$HOME/.fzf/install"
    else
        _check_cmd install fzf || true
        local file=/usr/share/doc/fzf/examples/key-bindings.zsh
        if [ ! -f "$file" ]; then
            $use_sudo $g_curl_opt -Lo "$file" "$g_url_fly_cdn/$(basename "$file")" || true
        fi
    fi

    # Install and configure oh-my-zsh
    _msg time "Install oh-my-zsh"
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        if ${IN_CHINA:-true}; then
            git clone --depth 1 "$g_url_ohmyzsh" "$HOME/.oh-my-zsh"
        else
            bash -c "$($g_curl_opt "$g_url_ohmyzsh")"
        fi
        cp -f "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$HOME/.zshrc"
        sed -i -e "/^ZSH_THEME/s/robbyrussell/ys/" "$HOME/.zshrc"

        local plugins="git z extract docker docker-compose"
        _check_cmd fzf && plugins="$plugins fzf"
        sed -i -e "/^plugins=.*git/s/git/$plugins/" "$HOME/.zshrc"
    fi

    # Install byobu
    _msg time "Install byobu"
    _check_cmd install byobu
    _msg time "End install zsh and byobu"
}

install_trzsz() {
    _check_cmd trz && {
        _msg warn "skip trzsz install"
        return 0
    }

    _msg step "Install trzsz"
    if command -v apt; then
        $cmd_pkg install -yq software-properties-common
        $use_sudo add-apt-repository --yes ppa:trzsz/ppa
        $cmd_pkg update -yq && $cmd_pkg install -yq trzsz
    elif command -v rpm; then
        $use_sudo rpm -ivh https://mirrors.wlnmp.com/centos/wlnmp-release-centos.noarch.rpm || true
        $cmd_pkg install -y trzsz
    else
        _msg warn "not support install trzsz"
    fi
}

install_lsyncd() {
    _msg step "Install lsyncd"
    _check_cmd install lsyncd

    local lsyncd_conf=/etc/lsyncd/lsyncd.conf.lua
    local id_file="$HOME/.ssh/id_ed25519"

    # Setup lsyncd config
    [ -d /etc/lsyncd ] || $use_sudo mkdir /etc/lsyncd
    [ -f "$lsyncd_conf" ] || {
        _msg time "new lsyncd.conf.lua"
        $use_sudo cp -vf "$g_laradock_path/usvn/root$lsyncd_conf" "$lsyncd_conf"
    }
    _check_root || $use_sudo sed -i "s@/root/docker@$HOME/docker@g" "$lsyncd_conf"

    # Setup SSH key
    [ -f "$id_file" ] || {
        _msg time "new key, ssh-keygen"
        ssh-keygen -t ed25519 -f "$id_file" -N ''
    }

    # Configure hosts
    _msg time "config $lsyncd_conf"
    while read -rp "[$((++count))] Enter ssh host IP (enter q break): " ssh_host_ip; do
        [[ -z "$ssh_host_ip" || "$ssh_host_ip" == q ]] && break

        ssh-copy-id -o StrictHostKeyChecking=no -i "$id_file" "root@$ssh_host_ip"
        $use_sudo sed -i \
            -e "/^htmlhosts/ a '$ssh_host_ip:$g_laradock_html/'," \
            -e "/^nginxhosts/ a '$ssh_host_ip:$g_laradock_path/nginx/'," \
            "$lsyncd_conf"
    done
}

install_wg() {
    if [[ "${lsb_dist-}" =~ (centos|alinux|openEuler) ]]; then
        ${cmd_pkg-} install -y epel-release elrepo-release
        $cmd_pkg install -y yum-plugin-elrepo
        $cmd_pkg install -y kmod-wireguard wireguard-tools
    else
        $cmd_pkg install -yqq wireguard wireguard-tools
    fi
    $use_sudo modprobe wireguard
}

_handle_ssl_config() {
    # 搜索并复制SSL密钥文件
    local ssl_dir="$g_laradock_path/nginx/sites/ssl" zip key temp_dir
    [ -d "$ssl_dir" ] || mkdir -p "$ssl_dir"

    # 在HOME和/tmp目录下同时搜索nginx相关的密钥文件
    temp_dir=$(mktemp -d)
    find "$HOME" "/tmp" -maxdepth 1 -iname "*nginx*.zip" -iname "*nginx*.gz" -type f 2>/dev/null |
        while read -r zip; do
            if [[ "$zip" == *.zip ]]; then
                unzip -j "$zip" -d "$temp_dir"
            elif [[ "$zip" == *.gz ]]; then
                cp -f "$zip" "$temp_dir"
                (cd "$temp_dir" && gunzip "$zip")
            fi
        done
    find "$HOME" "/tmp" "$temp_dir" -maxdepth 1 -iname "*.key" -iname "*.crt" -iname "*.pem" -type f |
        while read -r key; do
            _msg time "找到SSL密钥文件 $key ，正在复制..."
            [[ "$key" == *.key ]] && cp -vf "$key" "$ssl_dir/default.key"
            [[ "$key" == *.crt ]] && cp -vf "$key" "$ssl_dir/default.pem"
            [[ "$key" == *.pem ]] && cp -vf "$key" "$ssl_dir/default.pem"
        done
    _msg green "已更新SSL密钥文件到: $ssl_dir/default.*"
    _reload_nginx
    rm -rf "$temp_dir"
}

_install_acme() {
    _install_acme_official
    local acme_home="$HOME/.acme.sh"

    local key="$g_laradock_home/nginx/sites/ssl/default.key"
    local pem="$g_laradock_home/nginx/sites/ssl/default.pem"

    if ! _check_root; then
        _check_sudo
        $use_sudo chown "$USER:$USER" "$(dirname "$key")"
        $use_sudo chgrp "$USER" "$key" "$pem"
        $use_sudo chmod g+w "$key" "$pem"
    fi

    domain="${1}"
    _msg time "your domain is: ${domain:-api.example.com}"
    case "$domain" in
    *.*.*)
        cd "$acme_home" || return 1
        ./acme.sh --issue -w "$g_laradock_html" -d "$domain"
        ./acme.sh --install-cert --key-file "$key" --fullchain-file "$pem" -d "$domain"
        ;;
    *)
        echo
        echo "Single host domain:"
        echo "  cd $acme_home && ./acme.sh --issue -w $g_laradock_html -d ${domain:-api.example.com}"
        echo "Wildcard domain:"
        echo "  cd $acme_home && ./acme.sh --issue -w $g_laradock_html -d ${domain:-example.com} -d '*.${domain:-example.com}'"
        echo "DNS API: [https://github.com/acmesh-official/acme.sh/wiki/dnsapi]"
        echo "export Ali_Key= ; export Ali_Secret="
        echo "  cd $acme_home && ./acme.sh --issue --dns dns_cf -d ${domain:-example.com} -d '*.${domain:-example.com}'"
        echo "Deploy cert"
        echo "  cd $acme_home && ./acme.sh --install-cert --key-file $key --fullchain-file $pem -d ${domain:-example.com}"
        ;;
    esac
    # openssl x509 -noout -text -in "$pem"
    local p
    for p in "$(dirname "$pem")"/*.pem; do
        echo "Found $p"
        openssl x509 -noout -dates -in "$pem"
    done
}

docker_service() {
    [ "${#args[@]}" -eq 0 ] && {
        _msg warn "no arguments for docker service"
        return 0
    }

    _msg step "Start docker service automatically..."
    cd "$g_laradock_path" || exit 1
    $dco up -d "${args[@]}"

    # Wait for services to start
    for arg in "${args[@]}"; do
        for ((i = 1; i <= 5; i++)); do
            $dco ps | grep -q "$arg" && break
            sleep 2
        done
    done
}

show_loading() {
    local pid=$1 message=${2:-"waiting"} start_time=$SECONDS
    printf "%s " "$message"
    while kill -0 "$pid" 2>/dev/null; do
        printf "."
        sleep 1
    done
    echo " done ($((SECONDS - start_time))s)"
}

get_image() {
    _msg step "Get docker image..."
    local docker_ver image_prefix image_mirror=registry.cn-hangzhou.aliyuncs.com/flyh5
    ## special case [tencentos|opencloudos]  Docker version 0.0.0-20241223130549-3b49deb, build 3b49deb
    docker_ver="$(docker --version | awk '{gsub(/[,]/,""); if ($3 ~ /^0\.0\.0-[0-9]+/) {split($3,a,"-"); print a[2]} else print int($3)}')"

    image_prefix="laradock-"
    ## docker version 24 以下使用 laradock_ 前缀
    if [ "$docker_ver" -le 19 ]; then
        ## special case [kylin V10] 使用 laradock- 前缀
        [ "$docker_ver" -eq 18 ] || image_prefix="laradock_"
    fi

    for i in "${args[@]}"; do
        _msg time "docker pull image $i ..."
        case $i in
        nginx)
            arg_check_nginx=true
            # $g_curl_opt -fLo - "$g_url_fly_cdn/laradock-nginx.tar" | docker load
            docker pull "${image_mirror}/nginx:laradock" >/dev/null 2>&1 &
            show_loading $! "Pulling nginx image"
            docker tag "${image_mirror}/nginx:laradock" "${image_prefix}nginx"
            ;;
        redis)
            # $g_curl_opt -fLo - "$g_url_fly_cdn/laradock-redis.tar" | docker load
            docker pull "${image_mirror}/redis:laradock" >/dev/null 2>&1 &
            show_loading $! "Pulling redis image"
            docker tag "${image_mirror}/redis:laradock" "${image_prefix}redis"
            ;;
        mysql)
            source <(grep '^MYSQL_VERSION=' "$g_laradock_env")
            docker pull "${image_mirror}/mysql:${MYSQL_VERSION}-base" >/dev/null 2>&1 &
            show_loading $! "Pulling mysql image"
            docker tag "${image_mirror}/mysql:${MYSQL_VERSION}-base" "${image_prefix}mysql"
            ;;
        spring)
            sed -i "/^JDK_VERSION=/s/=.*/=${g_java_ver}/" "$g_laradock_env"
            source <(grep '^JDK_VERSION=' "$g_laradock_env")
            arg_test_java=true
            docker pull "${image_mirror}/amazoncorretto:${g_java_ver}-base" >/dev/null 2>&1 &
            show_loading $! "Pulling spring image"
            docker tag "${image_mirror}/amazoncorretto:${g_java_ver}-base" "${image_prefix}spring"
            ;;
        nodejs)
            sed -i "/^NODE_VERSION=/s/=.*/=${g_node_ver}/" "$g_laradock_env"
            source <(grep '^NODE_VERSION=' "$g_laradock_env")
            docker pull "${image_mirror}/node:${g_node_ver}-slim" >/dev/null 2>&1 &
            show_loading $! "Pulling nodejs image"
            docker tag "${image_mirror}/node:${g_node_ver}-slim" "${image_prefix}nodejs"
            ;;
        php*)
            sed -i \
                -e "/^PHP_VERSION=/s/=.*/=${g_php_ver}/" \
                -e "/CHANGE_SOURCE=/s/false/$IN_CHINA/" "$g_laradock_env"
            arg_check_php=true
            docker pull "${image_mirror}/php:${g_php_ver}-base" >/dev/null 2>&1 &
            show_loading $! "Pulling php-fpm image"
            docker tag "${image_mirror}/php:${g_php_ver}-base" "${image_prefix}php-fpm"
            ;;
        esac
        ## 如果不是最后一个镜像，则休眠10秒缓解阿里云ACR限流
        if [ "$i" != "${args[-1]}" ]; then
            sleep 6 &
            show_loading $! "Waiting for 6 seconds to avoid rate limit"
        fi
    done
    ## remove image mirror
    docker image ls | grep "$image_mirror" | awk '{print $1":"$2}' | xargs -r -I% docker rmi -f % >/dev/null
}

check_nginx() {
    local path=${1:-""}

    _reload_nginx
    source <(grep 'NGINX_HOST_HTTP_PORT' "$g_laradock_env")
    $dco stop nginx && $dco up -d nginx

    # Ensure favicon exists
    local favicon="$g_laradock_html/favicon.ico"
    [ -f "$favicon" ] || $g_curl_opt -s -o "$favicon" "$g_url_fly_ico"
    echo "INDEX Page: $(date)" >"$g_laradock_html/index.html"

    # Test nginx connection
    _msg time "test nginx $path ..."
    for ((i = 1; i <= 5; i++)); do
        $g_curl_opt "http://localhost:${NGINX_HOST_HTTP_PORT}/${path}" && break
        echo "test nginx error...[$((i * 2))]s"
        sleep 2
    done
    echo
}

check_php_fpm() {
    local test_file="$g_laradock_html/test.php"

    $use_sudo chown "$USER:$USER" "$g_laradock_html"

    _msg time "Create test.php"
    $use_sudo cp -avf "$g_laradock_path/php-fpm/test.php" "$test_file"
    source "$g_laradock_env" 2>/dev/null
    sed -i \
        -e "s/ENV_REDIS_PASSWORD/$REDIS_PASSWORD/" \
        -e "s/ENV_MYSQL_USER/${MYSQL_USER-}/" \
        -e "s/ENV_MYSQL_PASSWORD/${MYSQL_PASSWORD-}/" \
        "$test_file"

    check_nginx "test.php"
}

check_spring() {
    _msg time "check spring..."
    if $dco ps | grep "spring.*Up"; then
        _msg green "container [spring] is up"
    else
        _msg red "container [spring] is down"
    fi
}

get_env_info() {
    set +e
    echo "####  服务器本机集成环境信息  ####"
    echo "####  客户如果有独立 redis/mysql 则忽略此信息"
    echo "####  代码内写标准端口 mysql:3306 / redis:6379"
    echo "####  此处显示端口只用于SSH端口转发映射(可能不同于标准端口)"
    grep -E '^REDIS_' "$g_laradock_env" | sed -n '1,3p'
    echo
    grep -E '^DB_HOST|^MYSQL_' "$g_laradock_env" | grep -vE 'MYSQL_ROOT_PASSWORD|MYSQL_ENTRYPOINT_INITDB|MYSQL_SLAVE_ID'
    echo
    grep -E '^JDK_VERSION' "$g_laradock_env"
    echo
    grep -E '^PHP_VERSION' "$g_laradock_env"
    echo
    grep -E '^NODE_VERSION' "$g_laradock_env"
}

mysql_shell() {
    cd "$g_laradock_path"
    source <(grep -E '^MYSQL_DATABASE=|^MYSQL_USER=|^MYSQL_PASSWORD=|^MYSQL_ROOT_PASSWORD=' "$g_laradock_env")
    local mysql_user=${1:-$MYSQL_USER}
    local mysql_password
    mysql_password=$([ "$mysql_user" = root ] && echo "$MYSQL_ROOT_PASSWORD" || echo "$MYSQL_PASSWORD")
    $dco exec mysql bash -c "LANG=C.UTF-8 MYSQL_PWD=$mysql_password mysql --no-defaults -u$mysql_user $MYSQL_DATABASE"
}

redis_shell() {
    cd "$g_laradock_path"
    redis_pass=$(awk -F= '/^REDIS_PASSWORD=/ {print $2}' "$g_laradock_env")
    $dco exec redis bash -c "REDISCLI_AUTH=$redis_pass redis-cli --no-auth-warning"
}

_upgrade_java() {
    $g_curl_opt $g_url_fly_cdn/spring.tar.gz | tar -C "$g_laradock_path"/ vzx
    $dco stop spring
    $dco rm -f
    $dco up -d spring
}

_upgrade_php() {
    $g_curl_opt $g_url_fly_cdn/tp.tar.gz | tar -C "$g_laradock_html"/ vzx
}

reset_laradock() {
    _msg step "Reset laradock service"
    cd "$g_laradock_path" && $dco stop && $dco rm -f
    $use_sudo rm -rf "$g_laradock_path" "$g_laradock_path/../../laradock-data/mysql"
}

_refresh_cdn() {
    set +e
    local bucket_name="${1:?need OSS bucket name}"
    local obj_path="${2:?need OSS path}"
    local region="${3:-cn-hangzhou}"
    local temp_file="/tmp/cdn.txt"
    local get_result local_saved object_type

    while true; do
        get_result=$(aliyun oss cat "oss://$bucket_name/cdn.txt" 2>/dev/null | head -n1)
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
    cdn                 Refresh CDN: [bucket-name domain.com/ cn-hangzhou]
EOF
    exit 1
}

parse_command_args() {
    args=()
    if [ "$#" -eq 0 ]; then
        auto_mode=true
        arg_need_docker=true
    fi

    while [ "$#" -gt 0 ]; do
        case "${1}" in
        redis)
            args+=(redis)
            set_sysctl=true
            ;;
        mysql | mysql-[0-9]*)
            args+=(mysql)
            [[ "${1}" == mysql-[0-9]* ]] && g_mysql_ver=${1#mysql-}
            ;;
        java | jdk | spring | java-[0-9]* | jdk-[0-9]* | spring-[0-9]*)
            args+=(spring)
            [[ "${1}" == java-[0-9]* ]] && g_java_ver=${1#java-}
            [[ "${1}" == jdk-[0-9]* ]] && g_java_ver=${1#jdk-}
            ;;
        php | fpm | fpm-[0-9]* | php-[0-9]* | php-fpm-[0-9]*)
            args+=(php-fpm)
            [[ "${1}" == php-[0-9]* ]] && g_php_ver=${1#php-}
            [[ "${1}" == php-fpm-[0-9]* ]] && g_php_ver=${1#php-fpm-}
            ;;
        node | nodejs | node-[0-9]* | nodejs-[0-9]*)
            args+=(nodejs)
            [[ "${1}" == node-[0-9]* ]] && g_node_ver=${1#node-}
            [[ "${1}" == nodejs-[0-9]* ]] && g_node_ver=${1#nodejs-}
            ;;
        nginx)
            args+=(nginx)
            ;;
        gitlab | git)
            args+=(gitlab)
            ;;
        svn | usvn)
            args+=(usvn)
            ;;
        upgrade)
            [[ "${args[*]}" == *php-fpm* ]] && arg_upgrade_php=true
            [[ "${args[*]}" == *spring* ]] && arg_upgrade_java=true
            auto_mode=false
            arg_need_docker=false
            ;;
        not-china | not-cn | ncn)
            IN_CHINA=false
            aliyun_mirror=false
            ;;
        install-docker-without-aliyun)
            aliyun_mirror=false
            arg_check_docker=true
            ;;
        zsh | install-zsh)
            arg_install_zsh=true
            arg_check_timezone=true
            arg_check_dependence=true
            auto_mode=false
            arg_need_docker=false
            ;;
        acme | install-acme)
            arg_install_acme=true
            arg_domain="$2"
            auto_mode=false
            arg_need_docker=false
            [ -n "$2" ] && shift
            ;;
        trzsz | install-trzsz)
            arg_install_trzsz=true
            arg_check_timezone=true
            arg_check_dependence=true
            auto_mode=false
            arg_need_docker=false
            ;;
        lsync | lsyncd | install-lsyncd)
            arg_install_lsyncd=true
            arg_check_dependence=true
            auto_mode=false
            arg_need_docker=false
            ;;
        wg | wireguard | install-wg)
            arg_install_wg=true
            arg_check_dependence=true
            auto_mode=false
            arg_need_docker=false
            ;;
        info)
            arg_env_info=true
            auto_mode=false
            arg_need_docker=false
            ;;
        mysql-cli)
            arg_mysql_cli=true
            arg_mysql_user="$2"
            auto_mode=false
            [ -z "$2" ] || shift
            ;;
        redis-cli)
            arg_redis_cli=true
            auto_mode=false
            ;;
        test)
            arg_check_nginx=true
            arg_check_php=true
            auto_mode=false
            ;;
        reset | clean | clear)
            arg_reset_laradock=true
            auto_mode=false
            ;;
        key)
            arg_insert_key=true
            ;;
        ssl)
            # arg_ssl=true
            _handle_ssl_config
            ;;
        cdn | refresh)
            shift
            arg_need_docker=false
            auto_mode=false
            _refresh_cdn "$@"
            return
            ;;
        *)
            _usage
            ;;
        esac
        shift
    done

    # auto mode
    if [ "${auto_mode:-true}" = true ]; then
        if [ ${#args[@]} -eq 0 ]; then
            args+=(redis mysql php-fpm spring nginx)
            echo -e "\033[0;33mEN: Using default args: [${args[*]}]\033[0m"
            echo -e "\033[0;33mCN: 没有提供任何参数，将使用默认参数: [${args[*]}]\033[0m"
        fi
        arg_check_dependence=true # Set to true for auto mode
    fi
    echo "The final args: ${args[*]}"

    ## need docker provider
    if [ "${arg_need_docker:-true}" = true ]; then
        arg_check_docker=true
        arg_check_laradock=true
        arg_check_laradock_env=true
        arg_start_docker_service=true
        arg_pull_image=true
        arg_check_dependence=true # Set to true when docker is needed
    fi

    IN_CHINA=${IN_CHINA:-true}
    g_php_ver=${g_php_ver:-8.1}
    g_java_ver=${g_java_ver:-8}
    g_mysql_ver=${g_mysql_ver:-8.0}
    g_node_ver=${g_node_ver:-20}

}

get_common() {
    local file="/tmp/common.sh" url="$g_deploy_raw/lib/common.sh"
    [ -f "$file" ] || curl -fsSLo "$file" "$url"
    if grep 'shellcheck shell=bash' "$file"; then
        . "$file"
    else
        _msg red "Library $file file is not valid"
        return 1
    fi
}

main() {
    SECONDS=0
    set -Eeo pipefail

    parse_command_args "$@"

    ## global variables g_* / 全局变量
    g_me_path="$(dirname "$(readlink -f "$0")")"
    g_me_name="$(basename "$0")"
    g_me_env="$g_me_path/${g_me_name}.env"
    g_me_log="$g_me_path/${g_me_name}.log"

    g_curl_opt='curl --connect-timeout 10 -fL'
    g_url_fly_cdn="http://oss.flyh6.com/d"
    g_url_keys_fly="$g_url_fly_cdn/flyh6.keys"
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

    get_common
    ## 确定 laradock 的安装目录
    ## 按以下优先级顺序选择:

    ## 1. 默认安装目录 ($HOME/docker/laradock)
    ## 支持 root 用户或普通用户
    g_laradock_home="$HOME"/docker/laradock

    ## 2. 获取当前脚本所在目录
    g_laradock_current="$g_me_path"

    ## 3. 检查当前目录是否已存在 laradock 安装
    if [[ -f "$g_laradock_current/fly.sh" && -f "$g_laradock_current/.env.example" ]]; then
        ## 如果当前目录已安装，则使用当前目录
        g_laradock_path="$g_laradock_current"
    ## 4. 检查默认目录是否已存在 laradock 安装
    elif [[ -f "$g_laradock_home/fly.sh" && -f "$g_laradock_home/.env.example" ]]; then
        ## 如果默认目录已安装，则使用默认目录
        g_laradock_path=$g_laradock_home
    else
        ## 5. 远程执行场景 (curl "remote_url" | bash -s args)
        ## 在当前目录下创建新的安装路径
        g_laradock_path="$g_laradock_current"/docker/laradock
    fi

    g_laradock_env="$g_laradock_path"/.env
    g_laradock_html="$(dirname "$g_laradock_path")"/html

    if ${arg_install_acme:-false}; then
        _install_acme "$arg_domain"
        return
    fi

    ${arg_check_dependence:-false} && check_dependence

    # These installations don't need docker compose, but need basic dependencies
    ${arg_install_trzsz:-false} && install_trzsz
    if ${arg_install_zsh:-false}; then
        _install_zsh
        return
    fi
    if ${arg_install_lsyncd:-false}; then
        install_lsyncd
        return
    fi
    if ${arg_install_wg:-false}; then
        install_wg
        return
    fi
    if ${arg_upgrade_php:-false}; then
        _upgrade_php
        return
    fi

    # Operations that need docker compose
    if ${arg_upgrade_java:-false}; then
        _upgrade_java
        return
    fi

    if ${arg_mysql_cli:-false}; then
        mysql_shell "$arg_mysql_user"
        return
    fi
    if ${arg_redis_cli:-false}; then
        redis_shell
        return
    fi
    if ${arg_env_info:-false}; then
        get_env_info
        return
    fi

    ${arg_check_docker:-true} && check_docker
    ## install docker, add normal user (not root) to group "docker", re-login
    ${need_logout:-false} && return

    if ${arg_reset_laradock:-false}; then
        reset_laradock
        return
    fi

    ${arg_check_timezone:-false} && _check_timezone

    ${arg_check_laradock:-false} && check_laradock

    ${arg_check_laradock_env:-false} && check_laradock_env

    ${arg_pull_image:-false} && get_image

    ${arg_start_docker_service:-false} && docker_service

    ${arg_check_nginx:-false} && check_nginx

    ${arg_check_php:-false} && check_php_fpm

    ${arg_test_java:-false} && check_spring
    echo "END"
}

main "$@"
