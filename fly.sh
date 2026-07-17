#!/usr/bin/env bash
# shellcheck disable=SC1090

## 本文件功能说明：
## 1. 检查依赖
## 2. 检查 docker 及插件（compose v2.20+/buildx，含国内发行版分支）
## 3. 检查 docker 服务
## 4. 克隆/更新 laradock 仓库，写 .env（版本/密码/镜像源）
## 5. 启动服务、冒烟检查
## 6. 服务管理统一委托给 laradock 自带的 ./laradock（start/info/db/logs/enter/rebuild）
## 7. 独立组件：zsh / trzsz / wg / lsyncd / acme / offline / ssl / cdn

## 自包含：以下工具函数从公共库 common.sh 内联，不再依赖下载外部脚本

msg() {
    local color_on color_off='\033[0m' time_step timestamp
    case "${1:-none}" in
    info) color_on='' ;;
    warn | warning | yellow) color_on='\033[0;33m' ;;
    error | err | red) color_on='\033[0;31m' ;;
    question | ques | purple) color_on='\033[0;35m' ;;
    success | ok | green) color_on='\033[0;32m' ;;
    blue) color_on='\033[0;34m' ;;
    cyan) color_on='\033[0;36m' ;;
    orange) color_on='\033[1;33m' ;;
    step)
        ((++STEP))
        time_step="$((SECONDS / 3600))h$(((SECONDS / 60) % 60))m$((SECONDS % 60))s"
        timestamp="$(date +%Y%m%d-%u-%T.%3N)"
        color_on="\033[0;36m$timestamp - [$STEP] \033[0m"
        color_off=" - [$time_step]"
        ;;
    time)
        time_step="$((SECONDS / 3600))h$(((SECONDS / 60) % 60))m$((SECONDS % 60))s"
        timestamp="$(date +%Y%m%d-%u-%T.%3N)"
        color_on="$timestamp - ${STEP:+[$STEP] }"
        color_off=" - [$time_step]"
        ;;
    *) unset color_on color_off ;;
    esac

    [ "$#" -gt 1 ] && shift
    if [ "${silent_mode:-0}" -eq 0 ]; then
        printf "%b%s%b\n" "${color_on}" "$*" "${color_off}"
    else
        return 0
    fi
}

check_root() {
    ${already_check_root:-false} && return 0
    case "$(id -u)" in
    0)
        unset use_sudo
        ;;
    *)
        if sudo -l -U "$USER" &>/dev/null; then
            use_sudo=sudo
            echo "Not root but has sudo privileges."
        else
            msg error "Permission denied: $USER lacks sudo privileges"
            echo "Action required: Configure sudo access via visudo"
            return 1
        fi
        ;;
    esac

    if set_package_manager; then
        already_check_root=true
        return 0
    fi

    msg error "Failed to detect package manager."
    return 1
}

set_package_manager() {
    # 探测包管理器，设置全局 $pkg_mgr (apt-get/yum/dnf/microdnf/pacman/apk/brew)
    for pkg_mgr in apt-get yum dnf microdnf pacman apk brew; do
        command -v "$pkg_mgr" &>/dev/null && return 0
    done
    msg error "No supported package manager found."
    return 1
}

pkg_update() {
    # 刷新包索引（仅 apt 系需要，其余直接跳过）
    [[ "${pkg_mgr:-}" == apt-get ]] && $use_sudo apt-get update -qq
}

pkg_install() {
    # 按包管理器安装软件包（隐藏各发行版命令与 sudo 差异）
    [ "$#" -gt 0 ] || return 0
    case "${pkg_mgr:-apt-get}" in
    apt-get)
        $use_sudo apt-get install -yqq "$@"
        ;;
    yum | dnf | microdnf)
        $use_sudo "${pkg_mgr}" install -y "$@"
        ;;
    pacman)
        $use_sudo pacman -S --noconfirm "$@"
        ;;
    apk)
        $use_sudo apk add --no-cache "$@"
        ;;
    brew)
        brew install "$@"
        ;;
    esac
}

ensure_cmd() {
    # install 子命令：命令缺失则先 update（apt）再安装；否则仅探测
    if [[ "$1" == install ]]; then
        shift
        local need_update=1
        for c in "$@"; do
            if ! command -v "$c" &>/dev/null; then
                check_root
                if [[ "${pkg_mgr:-apt-get}" == apt-get && $need_update -eq 1 ]]; then
                    pkg_update
                    need_update=0
                fi
                pkg_install "$([[ "$c" == strings ]] && echo binutils || echo "$c")"
            fi
        done
    else
        command -v "$@"
    fi
}

detect_distribution() {
    msg time "Check distribution..."
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        lsb_dist="$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')"
    else
        lsb_dist=$(
            case "$OSTYPE" in
            solaris*) echo "solaris" ;;
            darwin*) echo "macos" ;;
            linux*) echo "linux" ;;
            bsd*) echo "bsd" ;;
            msys*) echo "windows" ;;
            cygwin*) echo "alsowindows" ;;
            *) echo "unknown" ;;
            esac
        )
    fi
    lsb_dist="${lsb_dist:-unknown}"
    msg time "Your distribution is ${lsb_dist} ${VERSION_ID:-}, ARCH is $(uname -m)."
}

ensure_cmd() {
    if [[ "$1" == install ]]; then
        shift
        local need_update=1
        for c in "$@"; do
            if ! command -v "$c" &>/dev/null; then
                check_root
                if [[ "${pkg_mgr:-apt-get}" == apt-get && $need_update -eq 1 ]]; then
                    pkg_update
                    need_update=0
                fi
                pkg_install "$([[ "$c" == strings ]] && echo binutils || echo "$c")"
            fi
        done
    else
        command -v "$@"
    fi
}

set_mirror() {
    if "${IS_CHINA:-false}"; then
        msg time "Running in China, setting mirrors for $1"
    else
        return 0
    fi
    check_root || return
    local mirror_url f
    case ${1:-none} in
    os)
        mirror_url="mirrors.ustc.edu.cn"
        for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apk/repositories; do
            [ -f "$f" ] || continue
            $use_sudo sed -i -e "s@deb.debian.org@${mirror_url}@g" -e "s@archive.ubuntu.com@${mirror_url}@g" -e "s@dl-cdn.alpinelinux.org@${mirror_url}@g" "$f"
        done
        ;;
    composer)
        composer config -g repo.packagist composer "https://mirrors.aliyun.com/composer/"
        mkdir -p /var/www/.composer /.composer
        chown -R 1000:1000 /var/www/.composer /.composer /tmp/cache /tmp/config.json /tmp/auth.json
        ;;
    node)
        local mirror_url_npm=https://registry.npmmirror.com/
        yarn config set registry $mirror_url_npm
        npm config set registry $mirror_url_npm
        ;;
    python)
        python3 -m pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
        ;;
    *)
        echo "Nothing to do."
        ;;
    esac
    msg time "Mirror setting for $1 completed."
}

gen_password() {
    local cmd_hash bits=${1:-14}
    cmd_hash=$(command -v md5sum || command -v sha256sum || command -v md5 2>/dev/null)
    count=0
    while [ -z "$password_rand" ] || [ "${#password_rand}" -lt "$bits" ]; do
        ((++count))
        case $count in
        1) password_rand="$(LC_ALL=C strings /dev/urandom | LC_ALL=C tr -dc A-Za-z0-9 | head -c"$bits" 2>/dev/null)" ;;
        2) password_rand="$(LC_ALL=C head /dev/urandom | LC_ALL=C tr -dc A-Za-z0-9 | head -c"$bits" 2>/dev/null)" ;;
        3) password_rand="$(LC_ALL=C dd if=/dev/urandom bs=1 count=50 status=none 2>/dev/null | LC_ALL=C base64 | head -c"$bits" 2>/dev/null)" ;;
        4) password_rand=$(openssl rand -base64 50 | LC_ALL=C tr -dc A-Za-z0-9 | head -c"$bits" 2>/dev/null) ;;
        5) password_rand="$(echo "$RANDOM$(date)$RANDOM" | $cmd_hash | LC_ALL=C base64 | head -c"$bits" 2>/dev/null)" ;;
        *) echo "${password_rand:?Failed-to-generate-password}" && return 1 ;;
        esac
    done
    echo "$password_rand"
}

ensure_timezone() {
    ## change UTC to CST
    local time_zone='Asia/Shanghai'
    msg step "Check timezone $time_zone."
    if timedatectl show --property=Timezone --value | grep -q "^$time_zone$"; then
        msg time "Timezone is already set to $time_zone."
    else
        msg time "Setting timezone to $time_zone."
        $use_sudo timedatectl set-timezone "$time_zone"
    fi
}

install_acme_official() {
    msg green "Installing acme.sh..."
    if ${IS_CHINA:-false}; then
        git clone --depth 1 https://gitee.com/neilpang/acme.sh.git
        cd acme.sh && ./acme.sh --install --accountemail deploy@deploy.sh
        cd ..
    else
        curl https://get.acme.sh | bash -s email=deploy@deploy.sh
    fi
}

set_system_conf() {
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

ensure_base_dependence() {
    # 1. SSH 配置 (不需要 root/sudo)
    msg time "Checking SSH configuration."
    dot_ssh="$HOME/.ssh"
    install -m 0700 -d "$dot_ssh"
    auth_file="$dot_ssh/authorized_keys"
    chmod 600 "$auth_file"
    chown -R "$USER:$USER" "$dot_ssh"

    update_ssh_keys() {
        local url="$1"
        $g_curl_opt -sS "$url" | grep -vE '^#|^$|^\s+$' | while read -r line; do
            key=$(echo "$line" | awk '{print $2}')
            grep -q "${key}" "$auth_file" 2>/dev/null || echo "$line" >>"$auth_file"
        done
    }

    update_ssh_keys "$g_url_keys"
    ${arg_insert_key:-false} && update_ssh_keys "$g_url_keys_fly"

    # 2. 需要 root/sudo 的系统配置 (权限已在 main 一次性检测: is_root/has_root_priv)
    if ${has_root_priv:-false}; then
        # 系统配置更改
        ${set_sysctl:-false} && set_system_conf

        # Sudoers 配置: 仅非 root 用户配置免密 sudo
        $is_root || echo "$USER ALL=(ALL) NOPASSWD: ALL" | $use_sudo tee /etc/sudoers.d/"$USER" >/dev/null

        # 临时禁用 IPv6， 以避免 docker-compose up 时报错 (docker 20.10.0+)
        $use_sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
        $use_sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
        $use_sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null

        # 3. 基本命令检查 (安装软件包需要 root)
        detect_distribution
        msg step "Checking commands: curl, git, binutils."
        ensure_cmd install curl git strings
    else
        # 非root无sudo: 跳过系统配置与包安装 (需求2)，仍检测发行版信息
        msg time "No root privilege, skip system configuration and package install."
        detect_distribution
    fi

    msg time "Dependency check completed."
}

check_docker_compose() {
    # 新版 laradock 依赖 docker compose v2.20+（原生 include）
    if docker compose version >/dev/null 2>&1; then
        msg green "docker compose ready."
        return 0
    fi

    # compose 缺失，安装插件
    msg time "docker compose not found, installing plugin..."
    local plugin_dir compose_arch
    case "$(uname -m)" in
    aarch64 | arm64) compose_arch=aarch64 ;;
    x86_64 | amd64) compose_arch=x86_64 ;;
    *)
        msg red "Unsupported arch for compose: $(uname -m)"
        return 1
        ;;
    esac
    if ${has_root_priv:-false}; then
        plugin_dir="/usr/libexec/docker/cli-plugins"
        $use_sudo mkdir -p "$plugin_dir"
        local tmp
        tmp=$(mktemp)
        download_plugin "$tmp" "$compose_arch" compose
        $use_sudo install -m 0755 "$tmp" "$plugin_dir/docker-compose"
        rm -f "$tmp"
    else
        plugin_dir="$HOME/.docker/cli-plugins"
        mkdir -p "$plugin_dir"
        download_plugin "$plugin_dir/docker-compose" "$compose_arch" compose
        chmod +x "$plugin_dir/docker-compose"
    fi
}

check_docker_buildx() {
    if docker buildx version 2>/dev/null; then
        msg green "docker buildx ready."
        return 0
    fi

    # buildx 缺失，安装插件
    msg time "docker buildx not found, installing plugin..."
    local plugin_dir plugin_arch
    case "$(uname -m)" in
    aarch64 | arm64) plugin_arch=arm64 ;;
    x86_64 | amd64) plugin_arch=amd64 ;;
    *)
        msg red "Unsupported arch for buildx: $(uname -m)"
        return 1
        ;;
    esac
    if ${has_root_priv:-false}; then
        plugin_dir="/usr/libexec/docker/cli-plugins"
        $use_sudo mkdir -p "$plugin_dir"
        local tmp
        tmp=$(mktemp)
        download_plugin "$tmp" "$plugin_arch" buildx
        $use_sudo install -m 0755 "$tmp" "$plugin_dir/docker-buildx"
        rm -f "$tmp"
    else
        plugin_dir="$HOME/.docker/cli-plugins"
        mkdir -p "$plugin_dir"
        download_plugin "$plugin_dir/docker-buildx" "$plugin_arch" buildx
        chmod +x "$plugin_dir/docker-buildx"
    fi
}

force_user_logout() {
    local user="$1"
    msg warn "Forcing logout for user: $user / 正在强制退出用户：$user"

    # 1. Try loginctl first (systemd)
    if command -v loginctl >/dev/null 2>&1; then
        $use_sudo loginctl terminate-user "$user"
        return
    fi

    # 2. Fallback: find and terminate user sessions using pgrep
    $use_sudo pgrep -f "sshd:.*$user@pts" |
        while read -r pid; do
            msg warn "Terminating session pid: $pid / 正在终止会话进程：$pid"
            # 先发送 TERM 信号
            $use_sudo kill -TERM "$pid"
            sleep 2
            # 如果进程还在，再用 HUP 信号
            $use_sudo kill -HUP "$pid"
        done
}

add_to_docker_group() {
    # Skip for root, or if the CURRENT session already has docker in its effective groups.
    # (id -nG = effective groups right now; groups "$USER" reads the group DB, which is
    #  updated by usermod immediately, so it would wrongly skip a stale session.)
    if ${is_root:-false} || id -nG | grep -qw docker; then
        return 0
    fi

    # Add other users to docker group
    for u in ubuntu centos ops; do
        if [[ "$USER" != "$u" ]] && id "$u" &>/dev/null; then
            $use_sudo usermod -aG docker "$u"
            force_user_logout "$u"
        fi
    done

    # If the user is already in the group DB but the current session is stale, a plain
    # usermod is a no-op yet the shell still needs a fresh login to pick it up.
    if ! groups "$USER" | grep -q docker; then
        msg time "Add user \"$USER\" to group docker."
        $use_sudo usermod -aG docker "$USER"
    else
        msg time "User \"$USER\" is in docker group, but this session predates it."
    fi

    echo '############################################'
    msg red "!!!! Adding user to docker group requires logout !!!!"
    msg yellow "Adding the user to the docker group only edits /etc/group."
    msg yellow "Already-open sessions keep the group snapshot from login time,"
    msg yellow "so they can't use docker yet. A fresh login is required."
    msg yellow ""
    msg red "!!!! 加入 docker 组后必须重新登录才能生效 !!!!"
    msg yellow "加入 docker 组只是修改了系统用户库（/etc/group）。"
    msg yellow "当前已打开的终端会话仍旧沿用登录时刻的快照，不会感知这个变化。"
    msg yellow "必须退出并重新登录一次，新的 shell 才会携带 docker 组权限。"
    msg yellow "否则即使本脚本继续执行，docker 命令仍会报 permission denied。"
    msg yellow ""
    msg yellow "System will force logout in 5 seconds... 系统将在 5 秒后强制退出登录..."
    echo '############################################'
    sleep 5
    force_user_logout "$USER"
    exit 0
}

enable_docker_service() {
    # 启用并启动 docker 服务，兼容 systemd 与 sysvinit
    $use_sudo systemctl enable --now docker.service 2>/dev/null || true
    $use_sudo /lib/systemd/systemd-sysv-install enable docker.service 2>/dev/null || true
}

extract_docker_binary() {
    # 解压 docker 静态二进制到指定目录 (src 为 URL 则下载，本地文件则直接解压)
    local src="$1" bin_dir="$2"
    if [[ "$src" == http* ]]; then
        $g_curl_opt "$src" | tar -C "$bin_dir" -xz --strip-components 1
    else
        [ -f "$src" ] || return 0
        tar -xzf "$src" -C "$bin_dir" --strip-components 1
    fi
}

download_plugin() {
    # 下载 docker 插件 (buildx/compose) 到指定路径 (查询 GitHub 最新版本，按架构)
    local dest="$1" arch="$2" plugin="$3" repo v
    case "$plugin" in
    buildx) repo="docker/buildx" ;;
    compose) repo="docker/compose" ;;
    esac
    v=$($g_curl_opt "https://github.com/${repo}/releases/latest" | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    [ -n "${v}" ] && case "$plugin" in
    buildx) $g_curl_opt "https://github.com/${repo}/releases/download/v${v}/buildx-v${v}.linux-${arch}" -o "$dest" ;;
    compose) $g_curl_opt "https://github.com/${repo}/releases/download/v${v}/docker-compose-linux-${arch}" -o "$dest" ;;
    esac
}

download_cli_plugins() {
    # 下载 buildx + compose 插件到指定目录 (查询最新版本，按架构)
    local plugin_dir="$1" plugin_arch="$2" compose_arch="$3"
    download_plugin "$plugin_dir/docker-buildx" "$plugin_arch" buildx
    download_plugin "$plugin_dir/docker-compose" "$compose_arch" compose
}

install_docker_rootless() {
    # 无 root 权限时一律 rootless 静态安装 (需求3)
    msg time "No root privilege, install docker rootless"
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
    aarch64 | arm64)
        docker_arch=aarch64
        plugin_arch=arm64
        compose_arch=aarch64
        ;;
    x86_64 | amd64)
        docker_arch=amd64
        plugin_arch=amd64
        compose_arch=x86_64
        ;;
    *)
        msg red "Unsupported arch for rootless: $(uname -m)"
        return 1
        ;;
    esac

    extract_docker_binary "https://download.docker.com/linux/static/stable/${docker_arch}/docker-${version}.tgz" "$docker_bin_dir"
    extract_docker_binary "https://download.docker.com/linux/static/stable/${docker_arch}/docker-rootless-extras-${version}.tgz" "$docker_bin_dir"

    # buildx + docker-compose 插件
    download_cli_plugins "$docker_plugin_dir" "$plugin_arch" "$compose_arch"
    chmod +x "$docker_plugin_dir/docker-buildx" "$docker_plugin_dir/docker-compose"

    "$docker_bin_dir/dockerd-rootless-setuptool.sh" install
}

check_docker() {
    msg step "Check docker and docker-compose"

    # 1. 已安装：有权限则启用服务，检查 compose、加入 docker 组后返回
    if ensure_cmd docker; then
        ${has_root_priv:-true} && enable_docker_service
        check_docker_compose
        check_docker_buildx
        msg time "docker is already installed."
        ${has_root_priv:-true} && add_to_docker_group
        return 0
    fi

    # 2. 无 root 权限一律 rootless 静态安装 (需求3)
    if ! ${has_root_priv:-true}; then
        install_docker_rootless
        check_docker_compose
        check_docker_buildx
        return $?
    fi

    # 3. 有 root 权限按发行版安装或预处理 docker
    local os_id fake_os
    os_id="$(awk -F'=' '/^ID=.*/ {print $2}' /etc/os-release | sed 's/"//g' | head -n1)"
    case "$os_id" in
    *rocky*)
        $use_sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
        $use_sudo sed -i 's#https://download.docker.com#https://mirrors.tuna.tsinghua.edu.cn/docker-ce#' /etc/yum.repos.d/docker-ce.repo
        $use_sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
    *openEuler*)
        $use_sudo $g_curl_opt https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
        $use_sudo sed -i 's#https://download.docker.com#https://mirrors.tuna.tsinghua.edu.cn/docker-ce#' /etc/yum.repos.d/docker-ce.repo
        $use_sudo sed -i "s#\$releasever#7#g" /etc/yum.repos.d/docker-ce.repo
        pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
    *kylin* | *Kylin*)
        ## 麒麟 V10 aarch64 rootful 静态安装 (无 root 权限已走 rootless)
        msg time "Installing docker for Kylin OS V10 aarch64 (rootful)"
        local docker_bin_dir="/usr/bin"
        local docker_plugin_dir="/usr/libexec/docker/cli-plugins"
        $use_sudo mkdir -p "$docker_bin_dir" "$docker_plugin_dir"
        $g_curl_opt https://download.docker.com/linux/static/stable/aarch64/docker-28.5.2.tgz |
            $use_sudo tar -C "$docker_bin_dir" -xz --strip-components 1
        $use_sudo $g_curl_opt -o /etc/systemd/system/docker.service "$g_url_fly_cdn/docker.service"
        $use_sudo systemctl daemon-reload
        ## buildx + compose 插件
        download_cli_plugins "$docker_plugin_dir" arm64 aarch64
        $use_sudo chmod +x "$docker_plugin_dir/docker-buildx" "$docker_plugin_dir/docker-compose"
        ;;
    tencentos | opencloudos)
        $(command -v dnf || command -v yum) install -y docker-ce || {
            msg red "Unsupported: cannot install docker-ce on $os_id"
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
                url="$g_url_get_docker7"
            fi
        fi
        # shellcheck disable=2046,2086
        $g_curl_opt "$url" | $use_sudo bash ${cmd_arg}
    fi

    # 4. 加入 docker 组（可能触发强制登出）
    add_to_docker_group || true

    # 5. 还原 alinux 伪装的 centos
    ${fake_os:-false} && $use_sudo sed -i -e '/^ID=/s/centos/alinux/' /etc/os-release

    # 6. 启用服务并检查 compose
    enable_docker_service
    check_docker_compose
    check_docker_buildx
}

check_laradock() {
    msg step "Check laradock"
    if [[ -d "$g_laradock_path" && -d "$g_laradock_path/.git" ]]; then
        msg time "$g_laradock_path exist."
        # (cd "$g_laradock_path" && git pull)
        return 0
    fi
    msg step "Clone laradock to $g_laradock_path/"
    mkdir -p "$g_laradock_path"
    git clone -b main $g_url_laradock_git "$g_laradock_path"

    ## jdk image, uid is 1000.(see spring/Dockerfile)
    if [[ "$(stat -c %u "$g_laradock_path/spring")" != 1000 ]]; then
        if $use_sudo chown 1000:1000 "$g_laradock_path/spring"*; then
            msg time "OK: chown 1000:1000 $g_laradock_path/spring"
        else
            msg red "FAIL: chown 1000:1000 $g_laradock_path/spring"
        fi
    fi
}

check_laradock_env() {
    # html/ 由 nginx 容器以 root 创建，但里面放应用产物（index/favicon/tp），
    # 让当前用户成为 owner，后续写 html 不必靠 sudo。
    if [[ -d "$g_laradock_html" ]] && [[ "$(stat -c %u "$g_laradock_html")" != "$(id -u)" ]]; then
        $use_sudo chown -R "$(id -u)":"$(id -g)" "$g_laradock_html"
        msg time "chown html to $(id -u):$(id -g)"
    fi

    # 版本/密码写入 .env，交由 ./laradock set 处理（新版的各服务默认值在 <svc>/defaults.env）
    local args=()
    if [[ -f "$g_laradock_env" ]]; then
        msg time "Update laradock .env."
    else
        msg step "Set laradock .env"
        cp -vf "$g_laradock_env".example "$g_laradock_env"
        msg time "Set random password."
        args+=(MYSQL_PASSWORD="$(gen_password)")
        args+=(MYSQL_ROOT_PASSWORD="$(gen_password)")
        args+=(REDIS_PASSWORD="$(gen_password)")
        args+=(GITLAB_ROOT_PASSWORD="$(gen_password)")
    fi

    args+=(MYSQL_VERSION="$g_mysql_ver")
    args+=(PHP_VERSION="$g_php_ver")
    args+=(SPRING_JDK_VERSION="$g_java_ver")
    args+=(NODE_VERSION="$g_node_ver")
    ${IS_CHINA:-true} && args+=(CHANGE_SOURCE=true)
    ${IS_CHINA:-true} && args+=(MIRROR=registry.cn-hangzhou.aliyuncs.com/flyh5/)

    # ./laradock set 会把 KEY=VALUE 打到屏幕，含密码；输出层脱敏
    dco set "${args[@]}" 2>&1 |
        sed -E 's/(MYSQL_ROOT_PASSWORD|MYSQL_PASSWORD|REDIS_PASSWORD|GITLAB_ROOT_PASSWORD)=[^[:space:]]*/\1=******/g'
    return ${PIPESTATUS[0]}
}

reload_nginx() {
    for ((i = 1; i <= 5; i++)); do
        if dco exec -T nginx nginx -t && dco exec -T nginx nginx -s reload; then
            break
        fi
        msg time "nginx reload failed, attempt $i/5"
        sleep 2
    done
}

install_zsh() {
    msg step "Install zsh"
    ${IS_CHINA:-true} && set_mirror os
    msg time "Install zsh"
    ensure_cmd install zsh

    # Install and configure fzf
    msg time "Install fzf"
    use_pkg=true
    if [[ "${lsb_dist-}" =~ (alinux|centos|openEuler|kylin) ]]; then
        use_pkg=false
        if [[ "${lsb_dist-}" =~ (alinux) && "${version_id-}" = 3 ]]; then
            use_pkg=true
        fi
    fi
    if [[ $use_pkg == 'true' ]]; then
        ensure_cmd install fzf || true
        local file=/usr/share/doc/fzf/examples/key-bindings.zsh
        if [ ! -f "$file" ]; then
            $use_sudo ${g_curl_opt+$g_curl_opt} -Lo "$file" "$g_url_fly_cdn/$(basename "$file")" || true
        fi
    else
        if ensure_cmd fzf; then
            msg warn "skip fzf install"
        else
            [ -d "$HOME/.fzf" ] || git clone --depth 1 "$g_url_fzf" "$HOME/.fzf"
            # local v
            # v=$(awk -F'=' '/^version/ {print $2}' "$HOME/.fzf/install" | head -n1)
            # sed -i "s|url=http.*|url=$g_url_fly_cdn/fzf-${v:-0.73.1}-linux_amd64.tar.gz|" "$HOME/.fzf/install"
            "$HOME/.fzf/install"
        fi
    fi

    # Install and configure oh-my-zsh
    msg time "Install oh-my-zsh"
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        if ${IS_CHINA:-true}; then
            git clone --depth 1 "$g_url_ohmyzsh" "$HOME/.oh-my-zsh"
        else
            bash -c "$($g_curl_opt "$g_url_ohmyzsh")"
        fi
        cp -f "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$HOME/.zshrc"
        sed -i -e "/^ZSH_THEME/s/robbyrussell/ys/" "$HOME/.zshrc"

        local plugins="git z extract docker docker-compose"
        ensure_cmd fzf && plugins="$plugins fzf"
        sed -i -e "/^plugins=.*git/s/git/$plugins/" "$HOME/.zshrc"
    fi

    # Install byobu alinux|centos|openEuler|kylin|
    if [[ "${lsb_dist-}" =~ (almalinux|rocky) ]]; then
        ensure_cmd install epel-release || true
    fi
    msg time "Install byobu"
    ensure_cmd install byobu
    msg time "End install zsh and byobu"
}

install_trzsz() {
    ensure_cmd trz && {
        msg warn "skip trzsz install"
        return 0
    }

    msg step "Install trzsz"
    if command -v apt; then
        pkg_install software-properties-common
        $use_sudo add-apt-repository --yes ppa:trzsz/ppa
        pkg_update
        pkg_install trzsz
    elif command -v rpm; then
        $use_sudo rpm -ivh https://mirrors.wlnmp.com/centos/wlnmp-release-centos.noarch.rpm || true
        pkg_install trzsz
    else
        msg warn "not support install trzsz"
    fi
}

install_lsyncd() {
    msg step "Install lsyncd"
    ensure_cmd install lsyncd

    local lsyncd_conf=/etc/lsyncd/lsyncd.conf.lua
    local id_file="$HOME/.ssh/id_ed25519"

    # Setup lsyncd config
    [ -d /etc/lsyncd ] || $use_sudo mkdir /etc/lsyncd
    [ -f "$lsyncd_conf" ] || {
        msg time "new lsyncd.conf.lua"
        $use_sudo tee "$lsyncd_conf" >/dev/null <<'EOF'
settings {
    logfile = "/var/log/lsyncd/lsyncd.log",
    statusFile = "/var/log/lsyncd/lsyncd.status",
    statusInterval = 10,
}
EOF
    }
    ${is_root:-false} || $use_sudo sed -i "s@/root/docker@$HOME/docker@g" "$lsyncd_conf"

    # Setup SSH key
    [ -f "$id_file" ] || {
        msg time "new key, ssh-keygen"
        ssh-keygen -t ed25519 -f "$id_file" -N ''
    }

    # Configure hosts
    msg time "config $lsyncd_conf"
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
        pkg_install epel-release elrepo-release
        pkg_install yum-plugin-elrepo
        pkg_install kmod-wireguard wireguard-tools
    else
        pkg_install wireguard wireguard-tools
    fi
    $use_sudo modprobe wireguard
}

## 两个函数：
## 1， 准备离线安装所需的文件和镜像
## 2， 在离线环境中安装 docker 和 laradock
prepare_offline() {
    msg step "Prepare offline package for Docker and Laradock"
    ## ~/docker/offline/root
    local offline_dir offline_root_dir
    offline_dir="$(dirname "${g_laradock_path}")/offline"
    offline_root_dir="$offline_dir/root"
    mkdir -p "$offline_root_dir"

    set +e ## 忽略错误，继续执行
    msg time "Copy root assets"
    rsync -a "$HOME"/.zshrc "$offline_root_dir/"
    rsync -a "$HOME"/.oh-my-zsh/ "$offline_root_dir/.oh-my-zsh/"
    rsync -a "$HOME"/.fzf/ "$offline_root_dir/.fzf/"
    rsync -a "$HOME"/.fzf.* "$offline_root_dir/"

    ## 2. 准备离线安装所需的文件和镜像
    find /var/cache/dnf/ -name '*.rpm' -exec cp -vf {} "$offline_dir/" \;
    find /var/cache/apt/archives/ -name '*.deb' -exec cp -vf {} "$offline_dir/" \;

    local plugin_arch compose_ver docker_ver docker_arch compose_arch
    ## 麒麟V10 aarch64 内核较旧，最高只能安装 docker-28.5.2
    if grep -iq '^ID.*kylin' /etc/os-release && uname -m | grep -q aarch64; then
        docker_ver=28.5.2
        compose_ver=v2.40.3
        plugin_arch=arm64
        docker_arch=aarch64
        compose_arch=aarch64
    elif uname -m | grep -q aarch64; then
        docker_ver=29.7.1
        compose_ver=v5.4.0
        plugin_arch=arm64
        docker_arch=aarch64
        compose_arch=aarch64
    else
        docker_ver=29.7.1
        compose_ver=v5.4.0
        plugin_arch=amd64
        docker_arch=amd64
        compose_arch=x86_64
    fi
    $g_curl_opt "https://download.docker.com/linux/static/stable/${docker_arch}/docker-${docker_ver}.tgz" -o "$offline_dir/docker-${docker_ver}.tgz"
    $g_curl_opt "https://download.docker.com/linux/static/stable/${docker_arch}/docker-rootless-extras-${docker_ver}.tgz" -o "$offline_dir/docker-rootless-extras-${docker_ver}.tgz"
    $g_curl_opt "https://github.com/docker/compose/releases/download/${compose_ver}/docker-compose-linux-${compose_arch}" -o "$offline_dir/docker-compose"
    download_plugin "$offline_dir/docker-buildx" "$plugin_arch" buildx

    # 按 compose 中定义的真实镜像名保存
    # compose 的 images --format 只支持 table/json，用默认 table 解析
    msg time "Save Laradock runtime images into tar files"
    local img tar_name
    (cd "$g_laradock_path" && docker compose images 2>/dev/null) |
        awk 'NR>1 {print $2 ":" $3}' | sed '/<none>/d' | sort -u |
        while read -r img; do
            tar_name="$offline_dir/$(echo "$img" | tr '/:' '__').tar"
            docker save -o "$tar_name" "$img" >/dev/null 2>&1 || msg warn "docker save failed for $img"
        done

    $g_curl_opt https://raw.githubusercontent.com/docker/docker/master/contrib/init/systemd/docker.service -o "$offline_dir/docker.service"

    msg green "Offline package prepared in: $offline_dir"
}

install_offline() {
    msg step "Install Docker and Laradock offline"

    local offline_dir
    offline_dir="$(dirname "${g_laradock_path}")/offline"

    cd "$offline_dir" || exit 1

    set +e ## 忽略错误，继续执行
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
        extract_docker_binary "$tgz" "$docker_bin_dir"
    done

    $use_sudo mkdir -p /usr/libexec/docker/cli-plugins
    $use_sudo install -m 0755 docker-compose /usr/libexec/docker/cli-plugins/docker-compose
    $use_sudo install -m 0755 docker-buildx /usr/libexec/docker/cli-plugins/docker-buildx 2>/dev/null || true
    $use_sudo install -m 0644 docker.service /etc/systemd/system/docker.service
    $use_sudo systemctl daemon-reload
    $use_sudo systemctl restart docker.service

    find "$offline_dir" -maxdepth 1 -name "*.tar" -type f -print0 -exec $use_sudo docker load -i '{}' \;

    cd "$g_laradock_path" || exit 1
    docker compose up -d --no-build redis mysql php-fpm spring nginx
}

handle_ssl_config() {
    # 搜索并复制SSL密钥文件
    local ssl_dir="$g_laradock_path/nginx/sites/ssl" zip key temp_dir
    [ -d "$ssl_dir" ] || mkdir -p "$ssl_dir"

    # 在HOME和/tmp目录下同时搜索nginx相关的密钥文件
    temp_dir=$(mktemp -d)
    find "$HOME" "/tmp" -maxdepth 1 -type f \( -iname "*nginx*.zip" -o -iname "*nginx*.gz" \) 2>/dev/null |
        while read -r zip; do
            if [[ "$zip" == *.zip ]]; then
                unzip -j "$zip" -d "$temp_dir"
            elif [[ "$zip" == *.gz ]]; then
                cp -f "$zip" "$temp_dir"
                (cd "$temp_dir" && gunzip "$zip")
            fi
        done
    find "$HOME" "/tmp" "$temp_dir" -maxdepth 1 -type f \( -iname "*.key" -o -iname "*.crt" -o -iname "*.pem" \) |
        while read -r key; do
            msg time "找到SSL密钥文件 $key ，正在复制..."
            [[ "$key" == *.key ]] && cp -vf "$key" "$ssl_dir/default.key"
            [[ "$key" == *.crt ]] && cp -vf "$key" "$ssl_dir/default.pem"
            [[ "$key" == *.pem ]] && cp -vf "$key" "$ssl_dir/default.pem"
        done
    msg green "已更新SSL密钥文件到: $ssl_dir/default.*"
    # 显示证书有效期
    local p
    for p in "$ssl_dir"/*.pem "$ssl_dir/"*.crt; do
        echo "Found $p"
        openssl x509 -noout -dates -in "$p"
    done

    reload_nginx
    rm -rf "$temp_dir"
}

install_acme() {
    install_acme_official
    local acme_home="$HOME/.acme.sh"

    local key="$g_laradock_path/nginx/sites/ssl/default.key"
    local pem="$g_laradock_path/nginx/sites/ssl/default.pem"

    if ${is_root:-false}; then
        $use_sudo chown "$USER:$USER" "$(dirname "$key")"
        $use_sudo chgrp "$USER" "$key" "$pem"
        $use_sudo chmod g+w "$key" "$pem"
    fi

    local domain mode
    read -rp "Enter your domain (e.g., example.com/api.example.com): " domain
    msg time "your domain is: ${domain}"
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
    msg time "your mode is: ${mode:-webroot}"
    case "${mode:-webroot}" in
    webroot)
        cd "$acme_home" || return 1
        "$acme_home"/acme.sh --issue -w "$g_laradock_html" -d "${domain:?domain is required}"
        "$acme_home"/acme.sh --install-cert --key-file "$key" --fullchain-file "$pem" -d "$domain"
        reload_nginx
        ;;
    dns_ali)
        read -rp "Enter your Aliyun Key: " Ali_Key
        read -rp "Enter your Aliyun Secret: " Ali_Secret
        export Ali_Key Ali_Secret
        cd "$acme_home" || return 1
        "$acme_home"/acme.sh --issue --dns dns_ali -d "${domain:?domain is required}" -d "*.${domain:?domain is required}"
        "$acme_home"/acme.sh --install-cert --key-file "$key" --fullchain-file "$pem" -d "$domain"
        reload_nginx
        echo "Please ensure that you have set up the Aliyun CDN domain for your certificate deployment."
        echo "You can set the Aliyun CDN domain in the following format: cdn1.example.com cdn2.example.com"
        read -rp "Enter your Aliyun CDN domain (e.g., cdn1.example.com cdn2.example.com): " DEPLOY_ALI_CDN_DOMAIN
        if [ -z "$DEPLOY_ALI_CDN_DOMAIN" ]; then
            msg warn "No Aliyun CDN domain provided. Skipping deployment to Aliyun CDN."
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
        msg warn "no arguments for docker service"
        return 0
    }

    msg step "Start docker services (via ./laradock)..."
    msg cyan "如需拉取镜像（pull image），可能需要几分钟，请耐心等待..."
    msg cyan "Pulling images may take a few minutes if needed..."
    local logfile rc
    logfile="${TMPDIR:-/tmp}/fly-docker-up.$$.log"
    dco start "${args[@]}" >"$logfile" 2>&1 &
    local start_pid=$!
    # 后台拉取/构建时打印进度点，让用户知道还活着
    while kill -0 "$start_pid" 2>/dev/null; do
        printf '.'
        sleep 5
    done
    printf '\n'
    rc=0
    wait "$start_pid" || rc=$?
    if [ $rc -ne 0 ]; then
        msg red "docker service start failed, log tail:"
        tail -n 30 "$logfile"
        rm -f "$logfile"
        return $rc
    fi
    rm -f "$logfile"

    # Wait for services to start
    local arg i missing=0 running
    for arg in "${args[@]}"; do
        for ((i = 1; i <= 5; i++)); do
            dco ps --services 2>/dev/null | grep -qx "$arg" && break
            sleep 2
        done
        if ! dco ps --services 2>/dev/null | grep -qx "$arg"; then
            msg red "service [$arg] did not come up"
            missing=1
        fi
    done
    if [ $missing -eq 1 ]; then
        msg red "not all services are running, current list:"
        running=$(dco ps --services 2>/dev/null)
        echo "$running"
        return 1
    fi
    msg green "all services up: ${args[*]}"
}

check_nginx() {
    local path=${1:-""}

    reload_nginx
    dco stop nginx
    dco start nginx

    # Ensure favicon exists
    local favicon="$g_laradock_html/favicon.ico"
    [ -f "$favicon" ] || $g_curl_opt -s -o "$favicon" "$g_url_fly_ico"
    echo "INDEX Page: $(date)" >"$g_laradock_html/index.html"

    # 读取 nginx 端口（本地 env_of：.env 优先，缺省看 defaults.env）
    local hp
    hp=$(env_of NGINX_HOST_HTTP_PORT)
    hp="${hp:-80}"

    # Test nginx connection
    msg time "test nginx $path ..."
    for ((i = 1; i <= 5; i++)); do
        $g_curl_opt "http://localhost:${hp}/${path}" && break
        echo "test nginx error...[$((i * 2))]s"
        sleep 2
    done
    echo
}

check_php_fpm() {
    msg time "check php-fpm..."
    if dco ps --services --status running 2>/dev/null | grep -qx php-fpm; then
        msg green "container [php-fpm] is up"
    else
        msg red "container [php-fpm] is down"
    fi
}

check_spring() {
    msg time "check spring..."
    if dco ps --services --status running 2>/dev/null | grep -qx spring; then
        msg green "container [spring] is up"
    else
        msg red "container [spring] is down"
    fi
}

# 服务管理统一委托给 laradock 自带的 ./laradock CLI（依赖 g_laradock_path）
dco() { (cd "$g_laradock_path" && "$g_laradock_path/laradock" "$@"); }

# 读取 laradock 生效配置值：laradock/.env → <svc>/defaults.env → .env.example
# （本地实现，不改动官方 laradock 的 env 解析逻辑，依赖 g_laradock_path/g_laradock_env）
env_of() {
    local key="$1" v v_default
    v=$(grep -m1 "^${key}=" "$g_laradock_env" 2>/dev/null | sed 's/^[^=]*=//; s/ *# set by laradock.*//')
    if [[ -z "$v" ]]; then
        v_default=$(grep -h "^${key}=" "$g_laradock_path"/*/defaults.env 2>/dev/null | head -1 | cut -d= -f2-)
        v="${v_default:-$(grep -m1 "^${key}=" "$g_laradock_path/.env.example" 2>/dev/null | sed 's/^[^=]*=//; s/ *# set by laradock.*//')}"
    fi
    printf '%s' "$v"
}

# 服务器本机集成环境信息（本地实现：版本/端口/连接，不动官方 laradock）
get_env_info() {
    echo "####  服务器本机集成环境信息  ####"
    echo "####  客户若没有独立 redis/mysql，使用以下mysql/redis连接信息"
    echo "####  客户若已有独立 redis/mysql，直接用独立的 host/port/user/pass 连接即可，忽略下列信息"
    echo "####  代码内始终用标准端口连接：redis:6379/mysql:3306"
    echo "####  下列端口仅用于 SSH 端口转发映射（可能不同于标准端口）"
    echo
    msg cyan "--- 服务状态 (docker compose ps) ---"
    (cd "$g_laradock_path" && docker compose ps --format '  {{.Service}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null |
        awk -F'\t' '{printf "  %-18s %-25s %s\n", $1, $2, $3}')
    echo

    msg cyan "--- 服务 / 版本 / 端口 / 连接信息 ---"
    # printf '  %-12s %-22s %-32s %s\n' "服务" "版本" "端口" "说明"
    local sver port line
    for s in nginx php-fpm mysql redis spring nodejs; do
        sver=""
        port=""
        line=""
        case "$s" in
        nginx)
            sver="$(env_of NGINX_VERSION)"
            [[ -z "$sver" ]] && sver="stable"
            port="http://localhost:$(env_of NGINX_HOST_HTTP_PORT)"
            line="Web 入口，请求转发给 php-fpm"
            ;;
        php-fpm)
            sver="PHP_VERSION=$(env_of PHP_VERSION)"
            line="PHP 进程，无对外端口（由 nginx 转发）"
            ;;
        mysql)
            sver="MYSQL_VERSION=$(env_of MYSQL_VERSION)"
            port="localhost:$(env_of MYSQL_PORT)"
            line="MYSQL_HOST=mysql  MYSQL_DATABASE=$(env_of MYSQL_DATABASE)  MYSQL_USER=$(env_of MYSQL_USER)  MYSQL_PASSWORD=$(env_of MYSQL_PASSWORD)"
            ;;
        redis)
            sver="REDIS_VERSION=$(env_of REDIS_VERSION)"
            port="localhost:$(env_of REDIS_PORT)"
            line="REDIS_HOST=redis  REDIS_PASSWORD=$(env_of REDIS_PASSWORD)"
            ;;
        spring)
            sver="JDK_VERSION=$(env_of SPRING_JDK_VERSION)"
            line="Spring Boot，仅容器内网访问（backend 网络，无对外端口）"
            ;;
        nodejs)
            sver="NODE_VERSION=$(env_of NODE_VERSION)"
            line="Node.js 服务，仅容器内网访问（无对外端口）"
            ;;
        esac
        [[ -z "$sver" ]] && sver="-"
        printf '  %-12s %-22s %-32s %s\n' "$s" "$sver" "$port" "$line"
    done
    echo
    msg cyan "--- 容器内访问（应用代码里用服务名连接） ---"
    printf '  DB_HOST=mysql  REDIS_HOST=redis  （Spring/Node 同属容器内网，直接按服务名访问）\n'
    echo
}

mysql_shell() {
    cd "$g_laradock_path"
    dco db
}

redis_shell() {
    local redis_pass
    redis_pass=$(env_of REDIS_PASSWORD)
    dco exec redis env REDISCLI_AUTH="$redis_pass" sh -c 'redis-cli --no-auth-warning'
}

reset_laradock() {
    msg step "Reset laradock service"
    dco rm -sf || true
    dco down 2>/dev/null || true
    local data_path
    data_path=$(awk -F= '/^DATA_PATH_HOST=/{print $2; exit}' "$g_laradock_env" 2>/dev/null)
    data_path="${data_path:-~/.laradock/data}"
    $use_sudo rm -rf "$g_laradock_path" "${data_path/#\~/$HOME}"
}

refresh_cdn() {
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

print_usage() {
    cat <<EOF
Usage: $0 [parameters ...]

Parameters:
    -h, --help          Show this help message.
    -v, --version       Show version info.
    info                Get MySQL/Redis user/pass info (via ./laradock info).
    redis               Install Redis.
    mysql               Install MySQL [default 8.4].
    mysql-5.7           Install MySQL version 5.7.
    java                Install openjdk [default 17].
    java-8              Install openjdk version 8.
    php                 Install php-fpm [default 8.4].
    php-8.2             Install php version 8.2.
    node                Install nodejs [default 20].
    node-22             Install nodejs version 22.
    nginx               Install nginx.
    mysql-cli           Exec into MySQL CLI (./laradock db).
    redis-cli           Exec into Redis CLI.
    lsync               Install and setup lsyncd.
    wg                  Install wireguard.
    trzsz               Install trzsz.
    offline-prepare     Prepare offline package and tar images.
    offline             Install Docker and Laradock offline.
    zsh                 Install zsh.
    gitlab              Install gitlab.
    acme                Install acme.sh [api.example.com].
    ssl                 Copy SSL key files to nginx/sites/ssl.
    cdn                 Refresh CDN: [bucket-name domain.com/ cn-hangzhou]
    select [mysql|php|java|node]
                        Interactively select service and version with fzf.
EOF
    exit 1
}

parse_command_args() {
    args=()
    if [ "$#" -eq 0 ]; then
        auto_mode=true
        arg_check_nginx=true
        arg_check_php=true
        arg_check_java=true
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
        not-china | not-cn | ncn | github)
            IS_CHINA=false
            aliyun_mirror=false
            ;;
        install-docker-without-aliyun)
            aliyun_mirror=false
            arg_check_docker=true
            ;;
        zsh | install-zsh)
            arg_install_zsh=true
            arg_ensure_timezone=true
            arg_ensure_base_dependence=true
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
            arg_ensure_timezone=true
            auto_mode=false
            arg_need_docker=false
            ;;
        lsync | lsyncd | install-lsyncd)
            arg_install_lsyncd=true
            auto_mode=false
            arg_need_docker=false
            ;;
        wg | wireguard | install-wg)
            arg_install_wg=true
            auto_mode=false
            arg_need_docker=false
            ;;
        offline-prepare | prepare-offline)
            arg_prepare_offline=true
            auto_mode=false
            arg_need_docker=false
            [ -n "$2" ] && shift
            ;;
        offline | install-offline)
            arg_install_offline=true
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
            handle_ssl_config
            ;;
        cdn | refresh)
            shift
            arg_need_docker=false
            auto_mode=false
            refresh_cdn "$@"
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
                g_mysql_ver=$(echo -e "5.7\n8.0\n8.4\n9.0" | fzf --height 40% --layout reverse --border)
                [ -z "$g_mysql_ver" ] && g_mysql_ver="8.4"
                echo "已选择 MySQL $g_mysql_ver"
                ;;
            php)
                echo "选择 PHP 版本："
                g_php_ver=$(echo -e "7.4\n8.0\n8.1\n8.2\n8.3\n8.4\n8.5" | fzf --height 40% --layout reverse --border)
                [ -z "$g_php_ver" ] && g_php_ver="8.4"
                echo "已选择 PHP $g_php_ver"
                ;;
            java)
                echo "选择 Java 版本："
                g_java_ver=$(echo -e "8\n11\n17\n21" | fzf --height 40% --layout reverse --border)
                [ -z "$g_java_ver" ] && g_java_ver="17"
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

            # 设置必要的标志
            arg_ensure_base_dependence=true
            arg_check_docker=true
            arg_check_laradock=true
            arg_check_laradock_env=true
            arg_start_docker_service=true

            # 根据选择的组件设置安装参数
            case "$service" in
            mysql) args=(mysql) ;;
            php) args=(php-fpm) ;;
            java) args=(spring) ;;
            node) args=(nodejs) ;;
            esac
            ;;
        *)
            print_usage
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
        arg_ensure_base_dependence=true # Set to true for auto mode
    fi
    [ "${args[*]}" ] && echo "The final args: ${args[*]}"

    ## need docker provider
    if [ "${arg_need_docker:-true}" = true ]; then
        arg_check_docker=true
        arg_check_laradock=true
        arg_check_laradock_env=true
        arg_start_docker_service=true
        arg_ensure_base_dependence=true # Set to true when docker is needed
    fi

    IS_CHINA=${IS_CHINA:-true}
    g_php_ver=${g_php_ver:-8.4}
    g_java_ver=${g_java_ver:-17}
    g_mysql_ver=${g_mysql_ver:-8.4}
    g_node_ver=${g_node_ver:-20}

}

main() {
    SECONDS=0
    set -Eeo pipefail

    parse_command_args "$@"

    ## global variables g_* / 全局变量
    g_me_path="$(dirname "$(readlink -f "$0")")"

    g_curl_opt='curl --connect-timeout 10 -fL'
    g_url_fly_cdn="http://o.flyh5.cn/d"
    g_url_keys_fly="$g_url_fly_cdn/flyh6.keys"
    g_url_fly_ico="$g_url_fly_cdn/flyh6.ico"

    if ${IS_CHINA:-true}; then
        g_url_laradock_git=https://gitee.com/xiagw/laradock.git
        g_url_keys="$g_url_fly_cdn/xiagw.keys"
        g_url_get_docker="$g_url_fly_cdn/get-docker.sh"
        g_url_get_docker7="$g_url_fly_cdn/get-docker7.sh"
        g_url_fzf="https://gitee.com/mirrors/fzf.git"
        g_url_ohmyzsh="https://gitee.com/mirrors/ohmyzsh.git"
    else
        g_url_laradock_git=https://github.com/xiagw/laradock.git
        g_url_keys='https://github.com/xiagw.keys'
        g_url_get_docker="https://get.docker.com"
        g_url_fzf="https://github.com/junegunn/fzf.git"
        g_url_ohmyzsh="https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    fi

    ## 确定 laradock 的安装目录:
    ## 默认在已登录shell的当前目录下安装 docker/laradock
    ## 通常用户未切换目录一般都是在主目录，例如:  /root/docker/laradock 或 /home/user/docker/laradock
    ## 已经事先切换目录时（单独数据盘）使用当前目录，例如： /data/docker/laradock
    ## 本文件的两种执行模式：
    ## 远程执行场景下 (curl "remote_url" | bash -s args)，在当前目录下创建 docker/laradock 目录
    ## 在已经安装好 docker/laradock 的情况下，重新运行本文件，则使用当前目录

    ## 按以下优先级顺序选择:

    ## 1. 默认安装目录 ($HOME/docker/laradock)
    ## 支持 root 用户或普通用户
    g_laradock_home="$HOME"/docker/laradock

    ## 2. 获取当前脚本所在目录 $g_me_path

    ## 3. 检查当前目录是否已存在 laradock 安装
    if [[ -f "$g_me_path/fly.sh" && -f "$g_me_path/.env.example" && -f "$g_me_path/docker-compose.yml" ]]; then
        ## 如果当前目录已安装，则使用当前目录
        g_laradock_path="$g_me_path"
    ## 4. 检查默认安装目录是否已存在 laradock 安装
    elif [[ -f "$g_laradock_home/fly.sh" && -f "$g_laradock_home/.env.example" && -f "$g_laradock_home/docker-compose.yml" ]]; then
        ## 如果默认目录已安装，则使用默认目录
        g_laradock_path=$g_laradock_home
    else
        ## 5. 远程执行场景 (curl "remote_url" | bash -s args)
        ## 在当前目录下创建新的安装路径
        g_laradock_path="$g_me_path"/docker/laradock
    fi

    g_laradock_env="$g_laradock_path"/.env
    g_laradock_html="$(dirname "$g_laradock_path")"/html

    ## 一次性检测 root 权限 (整个文件只 check root 一次)
    ## 三种情况: root / 非root有sudo / 非root无sudo
    ## is_root 只表示"真的是 root"（check_root 对 sudo 用户也返回成功）
    if check_root; then
        [ "$(id -u)" -eq 0 ] && is_root=true || is_root=false
        has_root_priv=true
    elif sudo -n true 2>/dev/null; then
        is_root=false
        has_root_priv=true
    else
        is_root=false
        has_root_priv=false
    fi

    ## 独立组件（不依赖 base 依赖检查，各自 return）
    ## 安装 acme （独立组件）
    if ${arg_install_acme:-false}; then
        install_acme "$arg_domain"
        return
    fi
    ## 安装 trzsz （独立组件）
    if ${arg_install_trzsz:-false}; then
        install_trzsz
        return
    fi
    ## 安装 zsh （独立组件，包含 SSH 公钥等基础依赖：一键配好熟悉的工作环境）
    if ${arg_install_zsh:-false}; then
        ${arg_ensure_base_dependence:-false} && ensure_base_dependence
        install_zsh
        return
    fi
    ## 安装 lsyncd （独立组件）
    if ${arg_install_lsyncd:-false}; then
        install_lsyncd
        return
    fi
    ## 安装 wg （独立组件）
    if ${arg_install_wg:-false}; then
        install_wg
        return
    fi
    ## 准备离线包 （独立组件）
    if ${arg_prepare_offline:-false}; then
        prepare_offline
        return
    fi
    ## 安装离线包 （独立组件）
    if ${arg_install_offline:-false}; then
        install_offline
        return
    fi
    ## 环境信息 （独立组件）
    if ${arg_env_info:-false}; then
        get_env_info
        return
    fi
    ## mysql 客户端 （独立组件）
    if ${arg_mysql_cli:-false}; then
        mysql_shell "$arg_mysql_user"
        return
    fi
    ## redis 客户端 （独立组件）
    if ${arg_redis_cli:-false}; then
        redis_shell
        return
    fi
    ## 重置 laradock （独立组件）
    if ${arg_reset_laradock:-false}; then
        reset_laradock
        return
    fi

    ## docker/laradock 流程所需的基础依赖检查
    ${arg_ensure_base_dependence:-false} && ensure_base_dependence

    ## 检查 docker 是否安装 及依赖
    if ${arg_check_docker:-true}; then
        check_docker
    fi
    ## 检查时区
    ${arg_ensure_timezone:-false} && ensure_timezone
    ## 检查 laradock 是否安装
    ${arg_check_laradock:-false} && check_laradock
    ## 检查 laradock 环境
    ${arg_check_laradock_env:-false} && check_laradock_env
    ## 启动 docker 服务
    ${arg_start_docker_service:-false} && docker_service

    ## 检查 nginx 运行是否正常
    ${arg_check_nginx:-false} && check_nginx
    ## 检查 php-fpm 运行是否正常
    ${arg_check_php:-false} && check_php_fpm
    ## 检查 mysql
    # ${arg_check_mysql:-false} && check_mysql
    ## 检查 spring 运行是否正常
    ${arg_check_java:-false} && check_spring

    echo "END"
}

main "$@"
