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
    # 1. SSH 配置 (不需要 sudo)
    _msg time "Checking SSH configuration."
    dot_ssh="$HOME/.ssh"
    auth_file="$dot_ssh/authorized_keys"
    [ -d "$dot_ssh" ] || mkdir -m 700 "$dot_ssh"

    update_ssh_keys() {
        local url="$1"
        $g_curl_opt -sS "$url" | grep -vE '^#|^$|^\s+$' | while read -r line; do
            key=$(echo "$line" | awk '{print $2}')
            grep -q "${key}" "$auth_file" 2>/dev/null || echo "$line" >>"$auth_file"
        done
    }

    update_ssh_keys "$g_url_keys"
    ${arg_insert_key:-false} && update_ssh_keys "$g_url_keys_fly"
    chmod 600 "$auth_file"

    # 2. 需要 sudo 的系统配置 (权限已在 main 一次性检测: is_root/has_root_priv)
    if ${has_root_priv:-false}; then
        # 系统配置更改
        ${set_sysctl:-false} && _set_system_conf

        # Sudoers 配置: 仅非 root 用户配置免密 sudo
        $is_root || echo "$USER ALL=(ALL) NOPASSWD: ALL" | $use_sudo tee /etc/sudoers.d/"$USER" >/dev/null

        # IPv6 配置
        $use_sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
        $use_sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
        $use_sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null

        # 3. 基本命令检查 (安装软件包需要 root)
        _check_distribution
        _msg step "Checking commands: curl, git, binutils."
        _check_cmd install curl git strings
    else
        # 非root无sudo: 跳过系统配置与包安装 (需求2)，仍检测发行版信息
        _msg time "No root privilege, skip system configuration and package install."
        _check_distribution
    fi

    _msg time "Dependency check completed."
}

check_docker_compose() {
    dco="docker compose"
    if $dco version 2>/dev/null; then
        _msg green "$dco ready."
        return 0
    fi
    dco="docker-compose"
    if _check_cmd $dco; then
        dco_ver=$($dco -v | awk '{gsub(/[,\.]/,""); print int($3)}')
        if [[ "$dco_ver" -lt 1190 ]]; then
            _msg warn "$dco version is too old."
        fi
        return 0
    fi

    # compose 缺失，安装插件
    _msg time "docker compose not found, installing plugin..."
    local plugin_dir compose_arch
    case "$(uname -m)" in
    aarch64 | arm64) compose_arch=aarch64 ;;
    x86_64 | amd64)  compose_arch=x86_64 ;;
    *) _msg red "Unsupported arch for compose: $(uname -m)"; return 1 ;;
    esac
    if ${has_root_priv:-false}; then
        plugin_dir="/usr/libexec/docker/cli-plugins"
        $use_sudo mkdir -p "$plugin_dir"
        local tmp; tmp=$(mktemp)
        _download_compose "$tmp" "$compose_arch"
        $use_sudo install -m 0755 "$tmp" "$plugin_dir/docker-compose"
        rm -f "$tmp"
    else
        plugin_dir="$HOME/.docker/cli-plugins"
        mkdir -p "$plugin_dir"
        _download_compose "$plugin_dir/docker-compose" "$compose_arch"
        chmod +x "$plugin_dir/docker-compose"
    fi
}

check_docker_buildx() {
    if docker buildx version 2>/dev/null; then
        _msg green "docker buildx ready."
        return 0
    fi

    # buildx 缺失，安装插件
    _msg time "docker buildx not found, installing plugin..."
    local plugin_dir plugin_arch
    case "$(uname -m)" in
    aarch64 | arm64) plugin_arch=arm64 ;;
    x86_64 | amd64)  plugin_arch=amd64 ;;
    *) _msg red "Unsupported arch for buildx: $(uname -m)"; return 1 ;;
    esac
    if ${has_root_priv:-false}; then
        plugin_dir="/usr/libexec/docker/cli-plugins"
        $use_sudo mkdir -p "$plugin_dir"
        local tmp; tmp=$(mktemp)
        _download_buildx "$tmp" "$plugin_arch"
        $use_sudo install -m 0755 "$tmp" "$plugin_dir/docker-buildx"
        rm -f "$tmp"
    else
        plugin_dir="$HOME/.docker/cli-plugins"
        mkdir -p "$plugin_dir"
        _download_buildx "$plugin_dir/docker-buildx" "$plugin_arch"
        chmod +x "$plugin_dir/docker-buildx"
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
    if ${is_root:-false} || groups "$USER" | grep -q docker; then
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
    exit 0
}

_enable_docker_service() {
    # 启用并启动 docker 服务，兼容 systemd 与 sysvinit
    $use_sudo systemctl enable --now docker.service 2>/dev/null || true
    $use_sudo /lib/systemd/systemd-sysv-install enable docker.service 2>/dev/null || true
}

_extract_docker_binary() {
    # 解压 docker 静态二进制到指定目录 (src 为 URL 则下载，本地文件则直接解压)
    local src="$1" bin_dir="$2"
    if [[ "$src" == http* ]]; then
        curl -fL "$src" | tar -C "$bin_dir" -xz --strip-components 1
    else
        [ -f "$src" ] || return 0
        tar -xzf "$src" -C "$bin_dir" --strip-components 1
    fi
}

_download_buildx() {
    # 下载 buildx 插件到指定路径 (查询 GitHub 最新版本，按架构)
    local dest="$1" arch="$2" v
    v=$(curl -fL https://github.com/docker/buildx/releases/latest | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    [ -n "$v" ] && curl -fL "https://github.com/docker/buildx/releases/download/v${v}/buildx-v${v}.linux-${arch}" -o "$dest"
}

_download_compose() {
    # 下载 compose 插件到指定路径 (查询 GitHub 最新版本，按架构)
    local dest="$1" arch="$2" v
    v=$(curl -fL https://github.com/docker/compose/releases/latest | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    [ -n "$v" ] && curl -fL "https://github.com/docker/compose/releases/download/v${v}/docker-compose-linux-${arch}" -o "$dest"
}

_download_cli_plugins() {
    # 下载 buildx + compose 插件到指定目录 (查询最新版本，按架构)
    local plugin_dir="$1" plugin_arch="$2" compose_arch="$3"
    _download_buildx "$plugin_dir/docker-buildx" "$plugin_arch"
    _download_compose "$plugin_dir/docker-compose" "$compose_arch"
}

_install_docker_rootless() {
    # 无 root 权限时一律 rootless 静态安装 (需求3)
    _msg time "No root privilege, install docker rootless"
    local docker_bin_dir="$HOME/bin"
    local docker_plugin_dir="$HOME/.docker/cli-plugins"
    mkdir -p "$docker_bin_dir" "$docker_plugin_dir"

    # 按架构选择静态二进制
    local docker_arch plugin_arch compose_arch version
    version="29.7.1"
    # kylin V10 aarch64 内核较旧，最高只支持 28.5.2
    if grep -q 'ID.*kylin' /etc/os-release && uname -m | grep -q aarch64; then
        version="28.5.2"
    fi
    case "$(uname -m)" in
    aarch64 | arm64) docker_arch=aarch64; plugin_arch=arm64; compose_arch=aarch64 ;;
    x86_64 | amd64)  docker_arch=amd64;  plugin_arch=amd64;  compose_arch=x86_64 ;;
    *)
        _msg red "Unsupported arch for rootless: $(uname -m)"
        return 1
        ;;
    esac

    _extract_docker_binary "https://download.docker.com/linux/static/stable/${docker_arch}/docker-${version}.tgz" "$docker_bin_dir"
    _extract_docker_binary "https://download.docker.com/linux/static/stable/${docker_arch}/docker-rootless-extras-${version}.tgz" "$docker_bin_dir"

    # buildx + docker-compose 插件
    _download_cli_plugins "$docker_plugin_dir" "$plugin_arch" "$compose_arch"
    chmod +x "$docker_plugin_dir/docker-buildx" "$docker_plugin_dir/docker-compose"

    "$docker_bin_dir/dockerd-rootless-setuptool.sh" install
}

check_docker() {
    _msg step "Check docker and docker-compose"

    # 1. 已安装：有权限则启用服务，检查 compose、加入 docker 组后返回
    if _check_cmd docker; then
        ${has_root_priv:-true} && _enable_docker_service
        check_docker_compose
        check_docker_buildx
        _msg time "docker is already installed."
        ${has_root_priv:-true} && add_to_docker_group
        return 0
    fi

    # 2. 无 root 权限一律 rootless 静态安装 (需求3)
    if ! ${has_root_priv:-true}; then
        _install_docker_rootless
        check_docker_compose
        check_docker_buildx
        return $?
    fi

    # 3. 有 root 权限按发行版安装或预处理 docker
    local os_id fake_os cmd_pkg2
    os_id="$(awk -F'=' '/^ID=.*/ {print $2}' /etc/os-release | sed 's/"//g' | head -n1)"
    case "$os_id" in
    *rocky*)
        $use_sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
        $use_sudo sed -i 's#https://download.docker.com#https://mirrors.tuna.tsinghua.edu.cn/docker-ce#' /etc/yum.repos.d/docker-ce.repo
        $use_sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
    *openEuler*)
        $use_sudo curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
        $use_sudo sed -i 's#https://download.docker.com#https://mirrors.tuna.tsinghua.edu.cn/docker-ce#' /etc/yum.repos.d/docker-ce.repo
        $use_sudo sed -i "s#\$releasever#7#g" /etc/yum.repos.d/docker-ce.repo
        ${cmd_pkg-} install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
    *kylin* | *Kylin*)
        ## 麒麟 V10 aarch64 rootful 静态安装 (无 root 权限已走 rootless)
        _msg time "Installing docker for Kylin OS V10 aarch64 (rootful)"
        local docker_bin_dir="/usr/bin"
        local docker_plugin_dir="/usr/libexec/docker/cli-plugins"
        $use_sudo mkdir -p "$docker_bin_dir" "$docker_plugin_dir"
        curl -fL https://download.docker.com/linux/static/stable/aarch64/docker-28.5.2.tgz |
            $use_sudo tar -C "$docker_bin_dir" -xz --strip-components 1
        $use_sudo curl -fLo /etc/systemd/system/docker.service "$g_url_fly_cdn/docker.service"
        $use_sudo systemctl daemon-reload
        ## buildx + compose 插件
        _download_cli_plugins "$docker_plugin_dir" arm64 aarch64
        $use_sudo chmod +x "$docker_plugin_dir/docker-buildx" "$docker_plugin_dir/docker-compose"
        ;;
    tencentos | opencloudos)
        cmd_pkg2="$(command -v dnf || command -v yum)"
        $cmd_pkg2 install -y docker-ce || {
            _msg red "Unsupported: cannot install docker-ce on $os_id"
            return 1
        }
        ;;
    *alinux*)
        # 伪装成 centos 以便后续 get-docker.sh 脚本识别
        $use_sudo sed -i -e '/^ID=/s/ID=.*/ID=centos/' /etc/os-release
        [ -f /etc/dnf/dnf.conf ] && echo 'exclude=dnf python3-dnf libsolv' >>/etc/dnf/dnf.conf
        fake_os=true
        ;;
    esac

    # 3. 仍未安装则用阿里云镜像 get-docker.sh 兜底
    if ! command -v docker >/dev/null 2>&1; then
        local url="$g_url_get_docker" cmd_arg
        if ${aliyun_mirror:-true}; then
            cmd_arg='-s - --mirror Aliyun'
            if [[ "${version_id-}" =~ ^[0-9]+$ && "${version_id%%.*}" -ne 7 ]]; then
                url="$g_url_get_docker2"
            fi
        fi
        if [ -z "${cmd_pkg2}" ]; then
            # shellcheck disable=2046,2086
            $g_curl_opt "$url" | $use_sudo bash ${cmd_arg}
        fi
    fi

    # 4. 加入 docker 组（可能触发强制登出）
    add_to_docker_group || true

    # 5. 还原 alinux 伪装的 centos
    ${fake_os:-false} && $use_sudo sed -i -e '/^ID=/s/centos/alinux/' /etc/os-release

    # 6. 启用服务并检查 compose
    _enable_docker_service
    check_docker_compose
    check_docker_buildx
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
    git clone -b china --depth 1 $g_url_laradock_git "$g_laradock_path"

    ## jdk image, uid is 1000.(see spring/Dockerfile)
    if [[ "$(stat -c %u "$g_laradock_path/spring")" != 1000 ]]; then
        if $use_sudo chown 1000:1000 "$g_laradock_path/spring"*; then
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
        -e "/^CHANGE_SOURCE=/s/false/$IS_CHINA/" \
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
    ${IS_CHINA:-true} && _set_mirror os
    _check_cmd install zsh

    # Install and configure fzf
    _msg time "Install fzf"
    use_pkg=true
    if [[ "${lsb_dist-}" =~ (alinux|centos|openEuler|kylin) ]]; then
        use_pkg=false
        if [[ "${lsb_dist-}" =~ (alinux) && "${version_id-}" = 3 ]]; then
            use_pkg=true
        fi
    fi
    if [[ $use_pkg == 'true' ]]; then
        _check_cmd install fzf || true
        local file=/usr/share/doc/fzf/examples/key-bindings.zsh
        if [ ! -f "$file" ]; then
            $use_sudo ${g_curl_opt+$g_curl_opt} -Lo "$file" "$g_url_fly_cdn/$(basename "$file")" || true
        fi
    else
        if _check_cmd fzf; then
            _msg warn "skip fzf install"
        else
            [ -d "$HOME/.fzf" ] || git clone --depth 1 "$g_url_fzf" "$HOME/.fzf"
            # local v
            # v=$(awk -F'=' '/^version/ {print $2}' "$HOME/.fzf/install" | head -n1)
            # sed -i "s|url=http.*|url=$g_url_fly_cdn/fzf-${v:-0.73.1}-linux_amd64.tar.gz|" "$HOME/.fzf/install"
            "$HOME/.fzf/install"
        fi
    fi

    # Install and configure oh-my-zsh
    _msg time "Install oh-my-zsh"
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        if ${IS_CHINA:-true}; then
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

    # Install byobu alinux|centos|openEuler|kylin|
    if [[ "${lsb_dist-}" =~ (almalinux|rocky) ]]; then
        _check_cmd install epel-release || true
    fi
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
    ${is_root:-false} || $use_sudo sed -i "s@/root/docker@$HOME/docker@g" "$lsyncd_conf"

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
    if [[ "${lsb_dist-}" =~ (centos|alinux|openEuler|almalinux) ]]; then
        ${cmd_pkg-} install -y epel-release elrepo-release
        $cmd_pkg install -y yum-plugin-elrepo
        $cmd_pkg install -y kmod-wireguard wireguard-tools
    else
        $cmd_pkg install -yqq wireguard wireguard-tools
    fi
    $use_sudo modprobe wireguard
}

## 两个函数：
## 1， 准备离线安装所需的文件和镜像
## 2， 在离线环境中安装 docker 和 laradock
prepare_offline() {
    _msg step "Prepare offline package for Docker and Laradock"
    ## ~/docker/offline/root
    local offline_dir
    offline_dir="$(dirname "${g_laradock_path}")/offline"
    local offline_root_dir="$offline_dir/root"
    mkdir -p "$offline_root_dir"

    set +e
    _msg time "Copy root assets"
    rsync -a $HOME/.zshrc "$offline_root_dir/"
    rsync -a $HOME/.oh-my-zsh/ "$offline_root_dir/.oh-my-zsh/"
    rsync -a $HOME/.fzf/ "$offline_root_dir/.fzf/"
    rsync -a $HOME/.fzf.* "$offline_root_dir/"

    ## 2. 准备离线安装所需的文件和镜像
    find /var/cache/dnf/ -name '*.rpm' -exec cp -vf {} "$offline_dir/" \;
    find /var/cache/apt/archives/ -name '*.deb' -exec cp -vf {} "$offline_dir/" \;

    ## 麒麟V10 aarch64 最高只能安装 docker-28.5.2.tgz docker-rootless-extras-28.5.2.tgz
    local plugin_arch
    if grep -q 'ID.*kylin' /etc/os-release && uname -m | grep -q aarch64; then
        curl -fL https://download.docker.com/linux/static/stable/aarch64/docker-28.5.2.tgz -o "$offline_dir/docker-28.5.2.tgz"
        curl -fL https://download.docker.com/linux/static/stable/aarch64/docker-rootless-extras-28.5.2.tgz -o "$offline_dir/docker-rootless-extras-28.5.2.tgz"
        curl -fL https://github.com/docker/compose/releases/download/v2.40.3/docker-compose-linux-aarch64 -o "$offline_dir/docker-compose"
        plugin_arch=arm64
    elif uname -m | grep -q aarch64; then
        curl -fL https://download.docker.com/linux/static/stable/aarch64/docker-29.7.1.tgz -o "$offline_dir/docker-29.7.1.tgz"
        curl -fL https://download.docker.com/linux/static/stable/aarch64/docker-rootless-extras-29.7.1.tgz -o "$offline_dir/docker-rootless-extras-29.7.1.tgz"
        curl -fL https://github.com/docker/compose/releases/download/v5.4.0/docker-compose-linux-aarch64 -o "$offline_dir/docker-compose"
        plugin_arch=arm64
    elif uname -m | grep -q x86_64; then
        curl -fL https://download.docker.com/linux/static/stable/amd64/docker-29.7.1.tgz -o "$offline_dir/docker-29.7.1.tgz"
        curl -fL https://download.docker.com/linux/static/stable/amd64/docker-rootless-extras-29.7.1.tgz -o "$offline_dir/docker-rootless-extras-29.7.1.tgz"
        curl -fL https://github.com/docker/compose/releases/download/v5.4.0/docker-compose-linux-x86_64 -o "$offline_dir/docker-compose"
        plugin_arch=amd64
    fi
    _download_buildx "$offline_dir/docker-buildx" "${plugin_arch:-arm64}"

    _msg time "Save standard Laradock images into tar files"
    local images=(
        "laradock-nginx"
        "laradock-redis"
        "laradock-mysql"
        "laradock-spring"
        "laradock-node"
        "laradock-php-fpm"
    )
    local image
    for image in "${images[@]}"; do
        docker save -o "$offline_dir/$image.tar" "$image" >/dev/null 2>&1 || _msg warn "docker save failed for $image"
    done

    # curl -fLo "$offline_dir/docker.service" https://raw.githubusercontent.com/docker/docker/master/contrib/init/systemd/docker.service
    curl -fLo "$offline_dir/docker.service" $g_url_fly_cdn/docker.service

    _msg green "Offline package prepared in: $offline_dir"
}

install_offline() {
    _msg step "Install Docker and Laradock offline"

    local offline_dir
    offline_dir="$(dirname "${g_laradock_path}")/offline"

    cd "$offline_dir" || exit 1

    set +e
    $use_sudo rsync -a "$offline_dir/root/" /root/
    $use_sudo dnf localinstall -y --disablerepo=* ./*.rpm
    $use_sudo apt install -y ./*.deb
    ## 有 root 或 sudo 权限的用户可以直接安装到 /usr/bin 下
    ## 没有 root 或 sudo 权限的用户可以安装在 $HOME/bin 下
    local docker_bin_dir
    if ${is_root:-false}; then
        docker_bin_dir="/usr/bin"
    else
        docker_bin_dir="$HOME/bin"
        mkdir -p "$HOME/bin"
    fi
    for tgz in docker-*.tgz; do
        _extract_docker_binary "$tgz" "$docker_bin_dir"
    done

    $use_sudo mkdir -p /usr/libexec/docker/cli-plugins
    $use_sudo install -m 0755 docker-compose /usr/libexec/docker/cli-plugins/docker-compose
    $use_sudo install -m 0755 docker-buildx /usr/libexec/docker/cli-plugins/docker-buildx 2>/dev/null || true
    $use_sudo install -m 0644 docker.service /etc/systemd/system/docker.service
    $use_sudo systemctl daemon-reload
    $use_sudo systemctl restart docker.service

    # find . -maxdepth 1 -name "laradock*.tar" -type f -print0 | xargs -0 -n1 -I{} $use_sudo docker load -i '{}'
    find "$offline_dir" -maxdepth 1 -name "laradock*.tar" -type f -print0 -exec $use_sudo docker load -i '{}' \;

    cd "$g_laradock_path" || exit 1
    docker compose up -d redis mysql php-fpm spring nginx
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
    # 显示证书有效期
    local p
    for p in "$ssl_dir"/*.pem "$ssl_dir/"*.crt; do
        echo "Found $p"
        openssl x509 -noout -dates -in "$p"
    done

    _reload_nginx
    rm -rf "$temp_dir"
}

_install_acme() {
    _install_acme_official
    local acme_home="$HOME/.acme.sh"

    local key="$g_laradock_home/nginx/sites/ssl/default.key"
    local pem="$g_laradock_home/nginx/sites/ssl/default.pem"

    if ${is_root:-false}; then
        $use_sudo chown "$USER:$USER" "$(dirname "$key")"
        $use_sudo chgrp "$USER" "$key" "$pem"
        $use_sudo chmod g+w "$key" "$pem"
    fi

    local domain mode
    read -rp "Enter your domain (e.g., example.com/api.example.com): " domain
    _msg time "your domain is: ${domain}"
    cat <<EOF
Single host domain（单域名使用目录）:
    $acme_home/acme.sh --issue -w $g_laradock_html -d ${domain:-api.example.com}
Wildcard domain（通配符域名使用目录）:
    $acme_home/acme.sh --issue -w $g_laradock_html -d ${domain:-example.com} -d '*.${domain:-example.com}'

# DNS API: [https://github.com/acmesh-official/acme.sh/wiki/dnsapi]
# （手动 DNS） --yes-I-know-dns-manual-mode-enough-go-ahead-please
Wildcard domain（通配符域名使用dns_ali）:
    export Ali_Key=xxxx
    export Ali_Secret=yyyy
    $acme_home/acme.sh --issue --dns dns_ali -d ${domain:-example.com} -d '*.${domain:-example.com}'
Deploy cert
    $acme_home/acme.sh --install-cert --key-file $key --fullchain-file $pem -d ${domain:-example.com}
Deploy cert with Aliyun CDN
    export Ali_Key=xxxx
    export Ali_Secret=yyyy
    export DEPLOY_ALI_CDN_DOMAIN="cdn1.${domain:-example.com} cdn2.${domain:-example.com}"
    $acme_home/acme.sh --deploy -d ${domain:-example.com} --deploy-hook ali_cdn
EOF

    read -rp "Enter your mode (e.g., webroot/dns_ali/dns_cf): " mode
    _msg time "your mode is: ${mode:-webroot}"
    case "${mode:-webroot}" in
    webroot)
        cd "$acme_home" || return 1
        "$acme_home"/acme.sh --issue -w "$g_laradock_html" -d "${domain:?domain is required}"
        "$acme_home"/acme.sh --install-cert --key-file "$key" --fullchain-file "$pem" -d "$domain"
        _reload_nginx
        ;;
    dns_ali)
        read -rp "Enter your Aliyun Key: " Ali_Key
        read -rp "Enter your Aliyun Secret: " Ali_Secret
        export Ali_Key Ali_Secret
        cd "$acme_home" || return 1
        "$acme_home"/acme.sh --issue --dns dns_ali -d "${domain:?domain is required}" -d "*.${domain:?domain is required}"
        "$acme_home"/acme.sh --install-cert --key-file "$key" --fullchain-file "$pem" -d "$domain"
        _reload_nginx
        echo "Please ensure that you have set up the Aliyun CDN domain for your certificate deployment."
        echo "You can set the Aliyun CDN domain in the following format: cdn1.example.com cdn2.example.com"
        read -rp "Enter your Aliyun CDN domain (e.g., cdn1.example.com cdn2.example.com): " DEPLOY_ALI_CDN_DOMAIN
        if [ -z "$DEPLOY_ALI_CDN_DOMAIN" ]; then
            _msg warn "No Aliyun CDN domain provided. Skipping deployment to Aliyun CDN."
        else
            export DEPLOY_ALI_CDN_DOMAIN
            "$acme_home"/acme.sh --deploy -d "$domain" --deploy-hook ali_cdn
        fi
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

    grep -E '^(REDIS_HOST|REDIS_PORT|REDIS_PASSWORD|MYSQL_VERSION|MYSQL_HOST|MYSQL_PORT|MYSQL_DATABASE|MYSQL_USER|MYSQL_PASSWORD|JDK_VERSION|PHP_VERSION|NODE_VERSION)=' "$g_laradock_env" |
        awk '/^REDIS_/{if(!r++){print ""} print} /^MYSQL_/{if(!m++){print ""} print} /^JDK_VERSION|^PHP_VERSION|^NODE_VERSION/{print ""; print} '
}

mysql_shell() {
    cd "$g_laradock_path"
    check_docker_compose
    source <(grep -E '^MYSQL_DATABASE=|^MYSQL_USER=|^MYSQL_PASSWORD=|^MYSQL_ROOT_PASSWORD=' "$g_laradock_env")
    local mysql_user=${arg_mysql_user:-$MYSQL_USER}
    local mysql_password
    mysql_password=$([ "$mysql_user" = root ] && echo "$MYSQL_ROOT_PASSWORD" || echo "$MYSQL_PASSWORD")
    $dco exec mysql bash -c "LANG=C.UTF-8 MYSQL_PWD=$mysql_password mysql --no-defaults -u$mysql_user $MYSQL_DATABASE"
}

redis_shell() {
    cd "$g_laradock_path"
    check_docker_compose
    redis_pass=$(awk -F= '/^REDIS_PASSWORD=/ {print $2}' "$g_laradock_env")
    $dco exec redis bash -c "REDISCLI_AUTH=$redis_pass redis-cli --no-auth-warning"
}

reset_laradock() {
    _msg step "Reset laradock service"
    cd "$g_laradock_path" && $dco rm -sf
    $use_sudo rm -rf "$g_laradock_path" "$g_laradock_path/../../laradata/mysql"
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
    auto                Install all services (default when no args).
    info                Get MySQL/Redis user/pass info.
    redis               Install Redis.
    mysql               Install MySQL [default 8.0].
    mysql-5.7           Install MySQL version 5.7.
    java                Install openjdk-8.
    java-17             Install openjdk-17.
    php                 Install php-fpm [default 8.1].
    php-8.2             Install php version 8.2.
    node                Install nodejs [default 20].
    node-22             Install nodejs version 22.
    nginx               Install nginx.
    mysql-cli           Exec into MySQL CLI.
    redis-cli           Exec into Redis CLI.
    lsync               Install and setup lsyncd.
    offline-prepare     Prepare offline package and tar images.
    offline             Install Docker and Laradock offline.
    zsh                 Install zsh.
    gitlab              Install gitlab.
    acme                Install acme.sh [api.example.com].
    cdn                 Refresh CDN: [bucket-name domain.com/ cn-hangzhou]
    select [mysql|php|java|node]
                        Interactively select service and version with fzf.
EOF
    exit 1
}

parse_command_args() {
    args=()
    RUN=()
    [ "$#" -eq 0 ] && set -- auto

    while [ "$#" -gt 0 ]; do
        case "${1}" in
        auto)
            # 显式 auto 与无参数等价，走默认全流程
            ;;
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
        not-china | not-cn | ncn | github)
            IS_CHINA=false
            aliyun_mirror=false
            ;;
        install-docker-without-aliyun)
            aliyun_mirror=false
            ;;
        zsh | install-zsh)
            RUN+=(check_dependence _install_zsh)
            auto_mode=false
            ;;
        acme | install-acme)
            RUN+=(_install_acme)
            auto_mode=false
            [ -n "$2" ] && shift
            ;;
        trzsz | install-trzsz)
            RUN+=(check_dependence install_trzsz check_docker _check_timezone)
            auto_mode=false
            ;;
        lsync | lsyncd | install-lsyncd)
            RUN+=(check_dependence install_lsyncd)
            auto_mode=false
            ;;
        wg | wireguard | install-wg)
            RUN+=(check_dependence install_wg)
            auto_mode=false
            ;;
        offline-prepare | prepare-offline)
            RUN+=(prepare_offline)
            auto_mode=false
            [ -n "$2" ] && shift
            ;;
        offline | install-offline)
            RUN+=(install_offline)
            auto_mode=false
            ;;
        info)
            RUN+=(check_docker get_env_info)
            auto_mode=false
            ;;
        mysql-cli)
            RUN+=(check_docker mysql_shell)
            arg_mysql_user="$2"
            auto_mode=false
            [ -z "$2" ] || shift
            ;;
        redis-cli)
            RUN+=(check_docker redis_shell)
            auto_mode=false
            ;;
        test)
            RUN+=(check_dependence check_docker check_laradock check_laradock_env docker_service check_nginx check_php_fpm check_spring)
            auto_mode=false
            ;;
        reset | clean | clear)
            RUN+=(check_dependence check_docker reset_laradock)
            auto_mode=false
            ;;
        key)
            arg_insert_key=true
            ;;
        ssl)
            _handle_ssl_config
            ;;
        cdn | refresh)
            shift
            auto_mode=false
            _refresh_cdn "$@"
            return
            ;;
        select)
            auto_mode=false
            # 检查是否安装了 fzf
            if ! command -v fzf >/dev/null 2>&1; then
                echo "请先安装 fzf: ./fly.sh zsh"
                exit 1
            fi

            # 如果没有指定组件，则通过 fzf 交互选择
            service="${2:-}"
            [ -z "$service" ] && service=$(printf '%s\n' "mysql" "php" "java" "node" | fzf --height 40% --layout reverse --border)

            case "$service" in
            mysql)
                echo "选择 MySQL 版本："
                g_mysql_ver=$(echo -e "5.7\n8.0\n8.1\n9.0" | fzf --height 40% --layout reverse --border)
                [ -z "$g_mysql_ver" ] && g_mysql_ver="8.0"
                echo "已选择 MySQL $g_mysql_ver"
                ;;
            php)
                echo "选择 PHP 版本："
                g_php_ver=$(echo -e "7.3\n7.4\n8.0\n8.1\n8.2\n8.3\n8.4\n8.5" | fzf --height 40% --layout reverse --border)
                [ -z "$g_php_ver" ] && g_php_ver="8.1"
                echo "已选择 PHP $g_php_ver"
                ;;
            java)
                echo "选择 Java 版本："
                g_java_ver=$(echo -e "8\n11\n17\n21\n22" | fzf --height 40% --layout reverse --border)
                [ -z "$g_java_ver" ] && g_java_ver="8"
                echo "已选择 Java $g_java_ver"
                ;;
            node)
                echo "选择 Node.js 版本："
                g_node_ver=$(echo -e "16\n18\n20\n22\n24" | fzf --height 40% --layout reverse --border)
                [ -z "$g_node_ver" ] && g_node_ver="20"
                echo "已选择 Node.js $g_node_ver"
                ;;
            *)
                echo "错误：未知的组件 '$2'"
                echo "可用组件: mysql, php, java, node"
                exit 1
                ;;
            esac

            # 根据选择的组件设置安装参数
            case "$service" in
            mysql) args=(mysql) ;;
            php) args=(php-fpm) ;;
            java) args=(spring) ;;
            node) args=(nodejs) ;;
            esac
            RUN+=(check_dependence check_docker check_laradock check_laradock_env docker_service)
            ;;
        *)
            _usage
            ;;
        esac
        shift
    done

    # auto mode: 无参数默认全流程
    if [ "${auto_mode:-true}" = true ]; then
        if [ ${#args[@]} -eq 0 ]; then
            args+=(redis mysql php-fpm spring nginx)
            echo -e "\033[0;33mEN: Using default args: [${args[*]}]\033[0m"
            echo -e "\033[0;33mCN: 没有提供任何参数，将使用默认参数: [${args[*]}]\033[0m"
        fi
        RUN+=(check_dependence check_docker check_laradock check_laradock_env docker_service check_nginx check_php_fpm check_spring)
    fi
    [ "${args[*]}" ] && echo "The final args: ${args[*]}"

    IS_CHINA=${IS_CHINA:-true}
    g_php_ver=${g_php_ver:-8.1}
    g_java_ver=${g_java_ver:-8}
    g_mysql_ver=${g_mysql_ver:-8.0}
    g_node_ver=${g_node_ver:-20}
}

get_common() {
    local file="/tmp/common.sh" url="$g_deploy_raw/lib/common.sh"
    [ -f "$file" ] || curl -fsSLo "$file" "$url"
    if grep -q 'shellcheck shell=bash' "$file"; then
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
    g_url_fly_cdn="http://o.flyh5.cn/d"
    g_url_keys_fly="$g_url_fly_cdn/flyh6.keys"
    g_url_fly_ico="$g_url_fly_cdn/flyh6.ico"

    if ${IS_CHINA:-true}; then
        g_url_laradock_git=https://gitee.com/xiagw/laradock.git
        g_url_laradock_raw=https://gitee.com/xiagw/laradock/raw/china
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
    ## 确定 laradock 的安装目录:
    ## 默认在当前目录下安装 laradock，例如: /root/docker/laradock 或 /home/user/docker/laradock 或 /data/docker/laradock
    ## 通常如果未切换目录一般都是在主目录，例如 /root 或 /home/user
    ## 如果已经事先切换目录，则使用当前目录，例如 /data
    ## 远程执行场景下 (curl "remote_url" | bash -s args)，则在当前目录下创建 docker/laradock 目录
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

    ## 一次性检测 root 权限 (整个文件只 check root 一次)
    ## 三种情况: root / 非root有sudo / 非root无sudo
    if _check_root; then
        is_root=true
        has_root_priv=true
    elif sudo -n true 2>/dev/null; then
        is_root=false
        has_root_priv=true
    else
        is_root=false
        has_root_priv=false
    fi

    ## 按 parse_command_args 决定的 RUN 数组顺序执行
    for fn in "${RUN[@]}"; do
        "$fn"
    done

    echo "END"
}

main "$@"
