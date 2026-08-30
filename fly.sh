#!/usr/bin/env bash
# vim: set ft=sh ts=4 sw=4 et:
# shellcheck disable=SC1090,SC1091

## 本文件功能说明：
## 1. 探测发行版/架构/版本（全局 OS 数组，一次性查询，后续各处取用）
## 2. 检查依赖（包管理器探测、curl/git/zsh 等缺失时按发行版安装）
## 3. 检查 docker 及插件（compose v2.20+/buildx；优先官方 get.docker.com 装最新 docker-ce，
##    失败回退静态 rootful/rootless；kylin V10 aarch64 老内核特例静态装 28.5.2；aliyun 为默认镜像源）
## 4. 克隆 laradock 仓库（已存在则不更新），写 .env（版本/密码/镜像源）
## 5. 启动服务、冒烟检查（nginx/php-fpm/spring/redis/mysql）
## 6. 服务管理统一委托给 laradock 自带的 ./laradock（start/info/db/logs/enter/rebuild）
## 7. 独立组件：zsh / trzsz / wg / lsyncd / acme / ssl / offline / info / mysql-cli / redis-cli / reset
## 8. 开机自启：docker 服务、系统内核参数

## 全局关联数组 OS：发行版/版本/架构等系统信息，一次性探测后各处取用
declare -A OS=()

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
    ## is_root 只表示"真的是 root"（check_root 对 sudo 用户也返回成功）
    ## has_root_priv 表示 root 或有 sudo
    is_root=false
    has_root_priv=false
    ${already_check_root:-false} && return 0
    case "$(id -u)" in
    0)
        is_root=true
        has_root_priv=true
        unset use_sudo
        ;;
    *)
        if sudo -l -U "$USER" &>/dev/null; then
            is_root=false
            has_root_priv=true
            use_sudo=sudo
            msg orange "⚠️  Not root but has sudo privileges / 非 root 但有 sudo 权限"
        else
            msg error "⛔ Permission denied: $USER lacks sudo privileges / 权限不足"
            msg warn "🔧 Action required: Configure sudo access via visudo"
            return 1
        fi
        ;;
    esac

    if set_package_manager; then
        already_check_root=true
        return 0
    fi

    msg error "⛔ Failed to detect package manager / 未检测到支持的包管理器."
    return 1
}

# 支持的包管理器，探测顺序即优先顺序
SUPPORTED_PKG_MGRS=(apt-get yum dnf microdnf pacman apk brew)

set_package_manager() {
    # 探测包管理器，设置全局 $pkg_mgr
    local pm
    for pm in "${SUPPORTED_PKG_MGRS[@]}"; do
        if command -v "$pm" &>/dev/null; then
            pkg_mgr=$pm
            return 0
        fi
    done
    msg error "No supported package manager found."
    return 1
}

pkg_install() {
    # 按包管理器安装软件包（apt 系先刷新索引，同一次执行只刷新一次；命令名≠包名时调用处直接给包名，如 binutils/epel-release）
    [ "$#" -gt 0 ] || return 0
    local pm="${pkg_mgr:-apt-get}"
    case "$pm" in
    apt-get)
        if [[ "${pkg_updated:-0}" -ne 1 ]]; then
            msg time "Running apt-get update (fetching package index from mirrors)..."
            $use_sudo apt-get update
            pkg_updated=1
        fi
        $use_sudo apt-get install -yqq "$@"
        ;;
    yum | dnf | microdnf)
        $use_sudo "$pm" install -y "$@"
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
    *)
        msg error "Unsupported package manager: $pm"
        return 1
        ;;
    esac
}

## 统一探测发行版/版本/架构，一次性查询，结果存全局关联数组 OS，后续各处直接取用
detect_os_info() {
    local dist
    if [ -r /etc/os-release ]; then
        ## source 只是读取 ID/VERSION_ID 填充 OS 数组，读取后统一走 OS[id]/OS[version]
        . /etc/os-release
        dist="$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')"
    else
        case "$OSTYPE" in
        solaris*) dist="solaris" ;;
        darwin*) dist="macos" ;;
        linux*) dist="linux" ;;
        bsd*) dist="bsd" ;;
        msys*) dist="windows" ;;
        cygwin*) dist="alsowindows" ;;
        *) dist="unknown" ;;
        esac
    fi
    OS[id]="${dist:-unknown}"
    OS[version]="${VERSION_ID:-}"
    OS[arch]="$(uname -m)"
    case "${OS[arch]}" in
    aarch64 | arm64)
        OS[docker]=aarch64
        OS[plugin]=arm64
        OS[compose]=aarch64
        ;;
    x86_64 | amd64)
        OS[docker]=x86_64
        OS[plugin]=amd64
        OS[compose]=x86_64
        ;;
    *)
        msg warn "Unsupported arch: ${OS[arch]}"
        ;;
    esac
    msg time "Your distribution is ${OS[id]} ${OS[version]}, ARCH is ${OS[arch]}."
}

# 纯存在检查
cmd_exists() { command -v "$1" &>/dev/null; }

# 命令缺失时按包名安装（包名省略时默认等于命令名，如包名≠命令名时显式给第二个参数）
cmd_ensure() {
    local cmd="$1" pkg="${2:-$1}"
    cmd_exists "$cmd" || pkg_install "$pkg"
}

set_mirror() {
    if "${IS_CHINA}"; then
        msg time "Running in China, setting mirrors for $1"
    else
        return 0
    fi
    check_root || return
    local url_mirror f
    case ${1:-none} in
    os)
        url_mirror="mirrors.ustc.edu.cn"
        for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.sources /etc/apk/repositories; do
            [ -f "$f" ] || continue
            $use_sudo sed -i -e "s@deb.debian.org@${url_mirror}@g" -e "s@archive.ubuntu.com@${url_mirror}@g" -e "s@dl-cdn.alpinelinux.org@${url_mirror}@g" "$f"
        done
        ;;
    composer)
        composer config -g repo.packagist composer "https://mirrors.aliyun.com/composer/"
        mkdir -p /var/www/.composer /.composer
        chown -R 1000:1000 /var/www/.composer /.composer /tmp/cache /tmp/config.json /tmp/auth.json
        ;;
    node)
        local url_mirror=https://registry.npmmirror.com/
        yarn config set registry $url_mirror
        npm config set registry $url_mirror
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

# 密码字符集：去掉易混淆字符 0/O、1/I/l
G_PASSWORD_CHARSET='23456789ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz'

gen_password() {
    local bits=${1:-14} password_rand count=0
    while [ "${#password_rand}" -lt "$bits" ]; do
        ((++count))
        case $count in
        1) password_rand="$(LC_ALL=C tr -dc "$G_PASSWORD_CHARSET" </dev/urandom | head -c"$bits" 2>/dev/null)" ;;
        2) password_rand="$(openssl rand -base64 50 | LC_ALL=C tr -dc "$G_PASSWORD_CHARSET" | head -c"$bits" 2>/dev/null)" ;;
        3) password_rand="$(LC_ALL=C base64 </dev/urandom | LC_ALL=C tr -dc "$G_PASSWORD_CHARSET" | head -c"$bits" 2>/dev/null)" ;;
        *) msg error "Failed to generate password" && return 1 ;;
        esac
    done
    echo "$password_rand"
}

install_acme_official() {
    msg green "Installing acme.sh..."
    if "${IS_CHINA}"; then
        git clone --depth 1 https://gitee.com/neilpang/acme.sh.git
        (cd acme.sh && ./acme.sh --install --accountemail deploy@deploy.sh)
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
        local url_key="$1"
        local expect_sha="$2"
        local tmp actual_sha
        tmp="$(mktemp)" || return 0
        # 下载→比对哈希→匹配才合入，防中间人篡改(HTTP 明文链路)
        if ! $g_curl_opt -sS "$url_key" -o "$tmp"; then
            msg warn "SSH keys download failed, skip: $url_key"
            rm -f "$tmp"
            return 0
        fi
        actual_sha="$(sha256sum "$tmp" | awk '{print $1}')" || true
        if [[ "$actual_sha" != "$expect_sha" ]]; then
            msg warn "SSH keys hash mismatch, skip keys: $url_key (expect $expect_sha, got $actual_sha)"
            rm -f "$tmp"
            return 0
        fi
        grep -vE '^#|^$|^\s+$' "$tmp" | while read -r line; do
            key=$(echo "$line" | awk '{print $2}')
            grep -q "${key}" "$auth_file" 2>/dev/null || echo "$line" >>"$auth_file"
        done
        rm -f "$tmp"
    }

    # 固定 sha256 的 keys 来源（如改文件内容，需同步更新这里的哈希）
    update_ssh_keys "$g_url_keys" "$g_sha_keys"

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
        msg step "Checking commands: curl, git."
        cmd_ensure curl
        cmd_ensure git
    else
        # 非root无sudo: 跳过系统配置与包安装 (需求2)，发行版信息已在主流程 detect_os_info 探测
        msg time "No root privilege, skip system configuration and package install."
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
    local plugin_dir
    local compose_arch="${OS[compose]}"
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
    local plugin_dir
    local plugin_arch="${OS[plugin]}"
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
    local pids pid
    pids=$($use_sudo pgrep -f "sshd:.*$user@pts" 2>/dev/null) || true
    while read -r pid; do
        [ -n "$pid" ] || continue
        msg warn "Terminating session pid: $pid / 正在终止会话进程：$pid"
        # 先发送 TERM 信号
        $use_sudo kill -TERM "$pid" 2>/dev/null || true
        sleep 2
        # 如果进程还在，再用 HUP 信号
        $use_sudo kill -HUP "$pid" 2>/dev/null || true
    done <<<"$pids"
}

add_to_docker_group() {
    # Skip for root, or if the CURRENT session already has docker in its effective groups.
    # (id -nG = effective groups right now; groups "$USER" reads the group DB, which is
    #  updated by usermod immediately, so it would wrongly skip a stale session.)
    if ${is_root:-false} || id -nG | grep -qw docker; then
        return 0
    fi

    # 静态安装 / 部分 distro 包不会自动创建 docker 组，必须先建组
    # （组已存在时 groupadd 会报错，忽略即可）
    $use_sudo groupadd docker 2>/dev/null || true

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
    # 传入 --user 时操作用户级 systemd (rootless docker)，否则系统级
    if [[ "${1:-}" == "--user" ]]; then
        command -v systemctl >/dev/null 2>&1 || return 0
        systemctl --user enable --now docker.service 2>/dev/null || true
        return 0
    fi
    $use_sudo systemctl enable --now docker.service 2>/dev/null || true
    $use_sudo /lib/systemd/systemd-sysv-install enable docker.service 2>/dev/null || true
    # dockerd 只在启动时把 socket 属组设为 docker 组；首次启动若组还不存在，
    # socket 会落成 root:root，普通用户即使进了 docker 组也无权限。这里兜底固定。
    if $use_sudo test -S /var/run/docker.sock; then
        $use_sudo chgrp docker /var/run/docker.sock 2>/dev/null || true
        $use_sudo chmod g+rw /var/run/docker.sock 2>/dev/null || true
    fi
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

# 插件最新版本号：中国环境优先读 CDN 的 latest.txt（mirror-docker.sh 写入），
# 否则查 GitHub 的 releases/latest；失败自动回退另一源
plugin_version() {
    local repo="$1" plugin="$2" v=""
    local api_url="https://github.com/${repo}/releases/latest"
    local latest_txt="$g_url_fly_cdn/latest.txt"
    if "${IS_CHINA}"; then
        v=$($g_curl_opt "$latest_txt" 2>/dev/null | awk -F= -v k="$plugin" '$1==k{gsub(/[^0-9.]/,"",$2); print $2; exit}') || v=""
        [ -n "$v" ] || v=$($g_curl_opt "$api_url" | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' | head -n1) || v=""
    else
        v=$($g_curl_opt "$api_url" | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' | head -n1) || v=""
        [ -n "$v" ] || v=$($g_curl_opt "$latest_txt" 2>/dev/null | awk -F= -v k="$plugin" '$1==k{gsub(/[^0-9.]/,"",$2); print $2; exit}') || v=""
    fi
    echo "$v"
}

download_plugin() {
    # 下载 docker 插件 (buildx/compose) 到指定路径
    # CDN 镜像与官网 GitHub 同目录结构；按环境选源，失败自动回退另一源
    local dest="$1" arch="$2" plugin="$3" repo v cdn_file gh_url cdn_url
    case "$plugin" in
    buildx) repo="docker/buildx" ;;
    compose) repo="docker/compose" ;;
    esac
    v="$(plugin_version "$repo" "$plugin")"
    [ -n "${v}" ] || {
        msg warn "Failed to resolve version for $plugin, skip"
        return 1
    }
    case "$plugin" in
    buildx) cdn_file="docker/buildx/releases/download/v${v}/buildx-v${v}.linux-${arch}" ;;
    compose) cdn_file="docker/compose/releases/download/v${v}/docker-compose-linux-${arch}" ;;
    esac
    gh_url="https://github.com/${repo}/releases/download/v${v}/$(basename "$cdn_file")"
    cdn_url="$g_url_fly_cdn/${cdn_file}"
    # 中国环境优先 CDN（GitHub 可能不通），其它优先 GitHub；失败自动回退
    if "${IS_CHINA:-true}"; then
        $g_curl_opt "$cdn_url" -o "$dest" || $g_curl_opt "$gh_url" -o "$dest"
    else
        $g_curl_opt "$gh_url" -o "$dest" || $g_curl_opt "$cdn_url" -o "$dest"
    fi
}

download_cli_plugins() {
    # 下载 buildx + compose 插件到指定目录 (查询最新版本，按架构)
    local plugin_dir="$1" plugin_arch="$2" compose_arch="$3"
    download_plugin "$plugin_dir/docker-buildx" "$plugin_arch" buildx
    download_plugin "$plugin_dir/docker-compose" "$compose_arch" compose
}

# 静态安装 docker 的版本：kylin V10 aarch64 内核较旧，最高只支持 28.5.2
docker_static_version() {
    if [[ "${OS[id]}" == *kylin* ]] && [[ "${OS[arch]}" =~ aarch64|arm64 ]]; then
        echo 28.5.2
    else
        echo 29.7.1
    fi
}

# 优先用官方 get.docker.com 脚本安装最新 docker-ce（覆盖大多数发行版），
# 脚本先取 CDN 镜像（$g_url_fly_cdn/get-docker.sh），失败回退官方源；
# 安装失败返回非 0，由调用方回退到静态安装。中国环境加 --mirror Aliyun。
install_docker_official() {
    local mirror_args=() script ret
    "${IS_CHINA}" && mirror_args+=(--mirror Aliyun)
    msg time "Installing docker (official get.docker.com)..."
    script=$(mktemp)
    if "${IS_CHINA:-true}"; then
        $g_curl_opt "$g_url_fly_cdn/get-docker.sh" -o "$script" ||
            $g_curl_opt "https://get.docker.com" -o "$script" || {
            rm -f "$script"
            return 1
        }
    else
        $g_curl_opt "https://get.docker.com" -o "$script" || {
            rm -f "$script"
            return 1
        }
    fi
    # 先 --dry-run 验证脚本与参数无误，通过后才真正安装（--dry-run 只打印将执行的操作，不落盘）
    $use_sudo sh "$script" --dry-run "${mirror_args[@]}"
    ret=$?
    if [ $ret -ne 0 ]; then
        msg warn "get.docker.com dry-run failed (exit $ret), skip real install"
        rm -f "$script"
        return "$ret"
    fi
    $use_sudo sh "$script" "${mirror_args[@]}"
    ret=$?
    rm -f "$script"
    return "$ret"
}

# docker 静态包下载源：中国环境优先 CDN 镜像（官网同目录结构），失败回退官方 download.docker.com
docker_static_src() {
    local arch="$1" file="$2" cdn
    cdn="$g_url_fly_cdn/linux/static/stable/${arch}/${file}"
    if "${IS_CHINA}" && $g_curl_opt -I "$cdn" -o /dev/null 2>/dev/null; then
        echo "$cdn"
    else
        echo "https://download.docker.com/linux/static/stable/${arch}/${file}"
    fi
}

# 在本地生成 docker.service（不再从网络下载），用法: write_docker_service <目标路径> [sudo前缀]
write_docker_service() {
    local target="$1" sudo_cmd="${2:-}"
    $sudo_cmd tee "$target" >/dev/null <<'DOCKER_SERVICE_EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
DOCKER_SERVICE_EOF
}

install_docker_static() {
    # 静态二进制安装 docker，区分 root / no root
    # root: 装到 /usr/bin + systemd 系统服务；no root: 装到 $HOME/bin + systemctl --user
    local mode="${1:-rootful}" docker_arch plugin_arch compose_arch version
    docker_arch="${OS[docker]}"
    plugin_arch="${OS[plugin]}"
    compose_arch="${OS[compose]}"
    version="$(docker_static_version)"
    msg time "Installing docker (static) ${docker_arch} v${version} (${mode})"

    local docker_bin_dir docker_plugin_dir
    if [[ "$mode" == "rootless" ]]; then
        docker_bin_dir="$HOME/bin"
        docker_plugin_dir="$HOME/.docker/cli-plugins"
        mkdir -p "$docker_bin_dir" "$docker_plugin_dir"
        extract_docker_binary "$(docker_static_src "$docker_arch" "docker-${version}.tgz")" "$docker_bin_dir"
        extract_docker_binary "$(docker_static_src "$docker_arch" "docker-rootless-extras-${version}.tgz")" "$docker_bin_dir"
        # buildx + docker-compose 插件（三个归档目录名不同：docker 静态 aarch64/x86_64，buildx arm64/amd64，compose aarch64/x86_64）
        download_cli_plugins "$docker_plugin_dir" "$plugin_arch" "$compose_arch"
        chmod +x "$docker_plugin_dir/docker-buildx" "$docker_plugin_dir/docker-compose"
    else
        docker_bin_dir="/usr/bin"
        docker_plugin_dir="/usr/libexec/docker/cli-plugins"
        $use_sudo mkdir -p "$docker_bin_dir" "$docker_plugin_dir"
        $g_curl_opt "$(docker_static_src "$docker_arch" "docker-${version}.tgz")" |
            $use_sudo tar -C "$docker_bin_dir" -xz --strip-components 1
        write_docker_service /etc/systemd/system/docker.service "$use_sudo"
        $use_sudo systemctl daemon-reload
        # 插件先下载到用户临时目录再 sudo install，避免非 root sudoer 无权限直写 root 属主目录
        local tmp
        tmp="$(mktemp -d)"
        download_cli_plugins "$tmp" "$plugin_arch" "$compose_arch"
        $use_sudo install -m 0755 "$tmp/docker-buildx" "$docker_plugin_dir/docker-buildx"
        $use_sudo install -m 0755 "$tmp/docker-compose" "$docker_plugin_dir/docker-compose"
        rm -rf "$tmp"
    fi

    if [[ "$mode" == "rootless" ]]; then
        "$docker_bin_dir/dockerd-rootless-setuptool.sh" install
        enable_docker_service --user
    fi
}

check_docker() {
    msg step "Check docker and docker-compose"

    # 1. 已安装：有权限则启用服务，检查 compose、加入 docker 组后返回
    if cmd_exists docker; then
        ${has_root_priv:-true} && enable_docker_service
        check_docker_compose
        check_docker_buildx
        msg time "docker is already installed."
        ${has_root_priv:-true} && add_to_docker_group
        return 0
    fi

    # 2. 未安装：优先官方 get.docker.com 装最新 docker-ce（覆盖大多数发行版）；
    #    kylin V10 aarch64 老内核直接静态装 28.5.2（装最新会起不来）；
    #    无 root 只能 rootless 静态装（get.docker.com 需要 root）。
    if ${has_root_priv:-true}; then
        if [[ "${OS[id]}" == *kylin* ]] && [[ "${OS[arch]}" =~ aarch64|arm64 ]]; then
            msg warn "kylin aarch64 old kernel: install docker 28.5.2 via static."
            install_docker_static rootful
        elif install_docker_official; then
            msg green "docker installed via get.docker.com."
        else
            msg warn "get.docker.com install failed, fallback to static rootful."
            install_docker_static rootful
        fi
    else
        install_docker_static rootless
    fi

    # 3. 加入 docker 组（rootless 无需 docker 组，仅 rootful 需要；可能触发强制登出）
    if ${has_root_priv:-true}; then
        add_to_docker_group || true
    fi

    # 4. 启用服务并检查 compose
    if ${has_root_priv:-true}; then
        enable_docker_service
        check_docker_compose
        check_docker_buildx
    else
        check_docker_compose
        check_docker_buildx
    fi
}

check_laradock() {
    msg step "Check laradock"
    if [[ -d "$g_laradock_path" && -f "$g_laradock_path/docker-compose.yml" ]]; then
        msg time "$g_laradock_path exist."
        # (cd "$g_laradock_path" && git pull)
        return 0
    fi
    if cmd_exists git; then
        msg step "Clone laradock to $g_laradock_path/"
        mkdir -p "$g_laradock_path"
        git clone -b main $g_url_laradock_git "$g_laradock_path"
    else
        # 无 git（且通常无权限装系统包）时，从 gitee/github 下载源码归档解压（tar.gz，无需 unzip）
        msg step "Download laradock archive to $g_laradock_path/ (git unavailable)"
        mkdir -p "$g_laradock_path"
        local tmp
        tmp="$(mktemp -d)" || return 1
        if ! $g_curl_opt "$g_url_laradock_archive" -o "$tmp/laradock.tar.gz"; then
            msg red "Download laradock failed: $g_url_laradock_archive"
            rm -rf "$tmp"
            return 1
        fi
        tar -xzf "$tmp/laradock.tar.gz" -C "$g_laradock_path" --strip-components 1
        ret=$?
        rm -rf "$tmp"
        if [ $ret -ne 0 ]; then
            msg red "Extract laradock archive failed."
            return $ret
        fi
    fi

    ## jdk image, uid is 1000.(see spring/Dockerfile)
    ## spring/nodejs/golang 目录在 check_laradock_env 统一 mkdir + chown（clone 时还不存在，这里不处理）
}

check_laradock_env() {
    # html/ 由 nginx 容器以 root 创建，但里面放应用产物（index/favicon/tp），
    # 让当前用户成为 owner，后续写 html 不必靠 sudo。
    if [[ -d "$g_laradock_html" ]] && [[ "$(stat -c %u "$g_laradock_html")" != "$(id -u)" ]]; then
        $use_sudo chown -R "$(id -u)":"$(id -g)" "$g_laradock_html"
        msg time "chown html to $(id -u):$(id -g)"
    fi

    ## mysql 官方镜像 8.0.44 起，/docker-entrypoint-initdb.d 的读取在切换到 mysql 用户（uid 999）之后执行；
    ## bind mount 源目录若是 root 私有权限（0600/0700），mysql 用户 ls 直接报 Permission denied 起不来。
    ## 部署时统一规整为世界可读（目录 a+rX、文件去私权），新装/迁移都不再踩。
    local mysql_initdb_dir="$g_laradock_path/mysql/docker-entrypoint-initdb.d"
    $use_sudo mkdir -p "$mysql_initdb_dir"
    $use_sudo chmod -R a+rX "$mysql_initdb_dir"

    ## 新布局：web 内容统一在 www/ 下，laradock 仓库本体不再挂进 web 容器。
    ## spring/nodejs/golang 容器内 uid=1000，html 归当前用户。
    mkdir -p "$g_www_root"/html "$g_www_root"/spring "$g_www_root"/nodejs "$g_www_root"/golang
    ## mkdir 继承 umask，服务器 umask 严格时（如 0077）会建出 0700 目录，
    ## www 自身属 root，ftp/其他登录用户与容器（php-fpm=33、spring/nodejs=1000）都无法进入。
    ## 显式放开 world 可读可进（a+rX），但只放开 r/traverse 不改写权限（自己属主任然可写）。
    ${use_sudo:-} chmod -R a+rX "$g_www_root" 2>/dev/null || true
    ${use_sudo:-} chown -R 1000:1000 "$g_www_root"/spring "$g_www_root"/nodejs "$g_www_root"/golang 2>/dev/null || true

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
        args+=(GITLAB_POSTGRES_PASSWORD="$(gen_password)")
    fi

    args+=(MYSQL_VERSION="$g_mysql_ver")
    args+=(MYSQL_DATABASE="$g_mysql_db")
    args+=(MYSQL_USER="$g_mysql_user")
    args+=(PHP_VERSION="$g_php_ver")
    args+=(SPRING_JDK_VERSION="$g_java_ver")
    args+=(NODE_VERSION="$g_node_ver")
    ## 绝对路径写死 APP_CODE_PATH_HOST（随安装位置，数据盘可跟随），
    ## 比相对路径更稳：多版本/extends 服务不会发生基准偏移。
    args+=(APP_CODE_PATH_HOST="$g_www_root")
    "${IS_CHINA}" && args+=(CHANGE_SOURCE=true)
    "${IS_CHINA}" && args+=(MIRROR=registry.cn-hangzhou.aliyuncs.com/flyh5/)

    # ./laradock set 会把 KEY=VALUE 打到屏幕，含密码；输出层脱敏
    dco set "${args[@]}" 2>&1 |
        sed -E 's/(MYSQL_ROOT_PASSWORD|MYSQL_PASSWORD|REDIS_PASSWORD|GITLAB_ROOT_PASSWORD|GITLAB_POSTGRES_PASSWORD)=[^[:space:]]*/\1=******/g'
    return "${PIPESTATUS[0]}"
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
    "${IS_CHINA}" && set_mirror os
    cmd_ensure zsh

    # Install and configure fzf
    msg time "Install fzf"
    use_pkg=true
    if [[ "${OS[id]}" =~ (alinux|centos|openeuler|kylin) ]]; then
        use_pkg=false
        if [[ "${OS[id]}" =~ (alinux) && "${OS[version]}" = 3 ]]; then
            use_pkg=true
        fi
    fi
    if [[ $use_pkg == 'true' ]]; then
        cmd_ensure fzf || true
        local file=/usr/share/doc/fzf/examples/key-bindings.zsh
        if [ ! -f "$file" ]; then
            $use_sudo ${g_curl_opt+$g_curl_opt} -Lo "$file" "$g_url_fly_cdn/$(basename "$file")" || true
        fi
    else
        if cmd_exists fzf; then
            msg warn "skip fzf install"
        else
            [ -d "$HOME/.fzf" ] || git clone --depth 1 "$g_url_fzf" "$HOME/.fzf"
            # 中国环境仅当 CDN 确记录了 fzf 版本且对应档存在（HEAD 200）才换源，
            # 否则保留 GitHub 官方源；镜像库可能缺 fzf 档，盲目 sed 换源会 404 装不上。
            if "${IS_CHINA}"; then
                fzf_ver=$($g_curl_opt "$g_url_fly_cdn/latest.txt" 2>/dev/null | awk -F= '$1=="fzf"{print $2}') || true
                if [ -n "$fzf_ver" ] && $g_curl_opt -I -o /dev/null \
                    "$g_url_fly_cdn/fzf/releases/download/v${fzf_ver}/fzf-${fzf_ver}-linux_${OS[plugin]}.tar.gz" 2>/dev/null; then
                    sed -i "s|https://github.com/junegunn/fzf|$g_url_fly_cdn/fzf|g" "$HOME/.fzf/install"
                    sed -i "s|^version=.*|version=$fzf_ver|" "$HOME/.fzf/install"
                fi
            fi
            "$HOME/.fzf/install"
        fi
    fi

    # Install and configure oh-my-zsh
    msg time "Install oh-my-zsh"
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        if "${IS_CHINA}"; then
            git clone --depth 1 "$g_url_ohmyzsh" "$HOME/.oh-my-zsh"
        else
            bash -c "$($g_curl_opt "$g_url_ohmyzsh")"
        fi
        cp -f "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$HOME/.zshrc"
        sed -i -e "/^ZSH_THEME/s/robbyrussell/ys/" "$HOME/.zshrc"

        local plugins="git z extract docker docker-compose"
        cmd_exists fzf && plugins="$plugins fzf"
        sed -i -e "/^plugins=.*git/s/git/$plugins/" "$HOME/.zshrc"
    fi

    # Install byobu alinux|centos|openEuler|kylin|
    if [[ "${OS[id]}" =~ (almalinux|rocky) ]]; then
        pkg_install epel-release || true
    fi
    msg time "Install byobu"
    cmd_ensure byobu
    msg time "End install zsh and byobu"
}

install_trzsz() {
    cmd_exists trz && {
        msg warn "skip trzsz install"
        return 0
    }

    msg step "Install trzsz"
    if command -v apt; then
        pkg_install software-properties-common
        $use_sudo add-apt-repository --yes ppa:trzsz/ppa
        unset pkg_updated
        cmd_ensure trzsz
    elif command -v rpm; then
        $use_sudo rpm -ivh https://mirrors.wlnmp.com/centos/wlnmp-release-centos.noarch.rpm || true
        cmd_ensure trzsz
    else
        msg warn "not support install trzsz"
    fi
}

install_lsyncd() {
    msg step "Install lsyncd"
    cmd_ensure lsyncd

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
    if [[ "${OS[id]}" =~ (centos|alinux|openeuler|almalinux) ]]; then
        pkg_install epel-release elrepo-release
        pkg_install yum-plugin-elrepo
        pkg_install kmod-wireguard wireguard-tools
    else
        pkg_install wireguard wireguard-tools
    fi
    $use_sudo modprobe wireguard
}

# 从 GitHub API 取最新版本号（去 v 前缀），失败返回空
mirror_resolve_latest() {
    local repo="$1"
    $g_curl_opt "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null |
        awk -F'"' '/"tag_name"/{print $4; exit}' | sed 's/^v//'
}

# 下载到 mirror_dir/<path>，成功后上传 OSS；失败跳过（不 die，让其它项继续）
mirror_download() {
    local url="$1" file="$2"
    mkdir -p "$(dirname "$file")"
    msg cyan "download: $url"
    if $g_curl_opt "$url" -o "$file"; then
        msg cyan "  -> $file"
        mirror_upload "$file"
    else
        msg warn "download failed, skip: $url"
    fi
}

# 上传到 oss://<bucket>/d/<相对路径>
mirror_upload() {
    local file="$1" rel obj
    rel="${file#"$mirror_dir"/}"
    obj="d/$rel"
    msg cyan "oss upload: $rel -> oss://$arg_mirror_bucket/$obj"
    aliyun -p flyh6 ossutil -e "$mirror_endpoint" cp --force "$file" "oss://$arg_mirror_bucket/$obj" ||
        msg warn "oss upload failed: $obj"
}

## docker 静态包，保留官网目录结构 linux/static/stable/<arch>/
mirror_docker_static() {
    [ "${MIRROR_SKIP_DOCKER:-false}" = true ] && return 0
    local ver arch tgz url
    for ver in $mirror_docker_versions; do
        for arch in x86_64 aarch64; do
            for tgz in "docker-${ver}.tgz" "docker-rootless-extras-${ver}.tgz"; do
                url="https://download.docker.com/linux/static/stable/${arch}/${tgz}"
                mirror_download "$url" "$mirror_dir/linux/static/stable/${arch}/${tgz}"
            done
        done
    done
}

## compose + buildx 插件，保留 GitHub releases 目录结构 docker/<repo>/releases/download/v<ver>/
mirror_plugins() {
    local compose_ver buildx_ver os ca ba exe ca_list url
    compose_ver="$(mirror_resolve_latest docker/compose || true)"
    buildx_ver="$(mirror_resolve_latest docker/buildx || true)"
    [ -n "$compose_ver" ] || {
        msg warn "resolve compose latest failed, skip"
        return
    }
    [ -n "$buildx_ver" ] || {
        msg warn "resolve buildx latest failed, skip"
        return
    }
    msg cyan "compose v${compose_ver} / buildx v${buildx_ver}"

    for os in $mirror_os; do
        case "$os" in
        linux | darwin) ca_list="x86_64 aarch64" ;;
        windows) ca_list="x86_64" ;;
        *) continue ;;
        esac
        [ "$os" = windows ] && exe=".exe" || exe=""
        for ca in $ca_list; do
            ba=$(sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/' <<<"$ca")
            url="https://github.com/docker/compose/releases/download/v${compose_ver}/docker-compose-${os}-${ca}${exe}"
            mirror_download "$url" "$mirror_dir/docker/compose/releases/download/v${compose_ver}/docker-compose-${os}-${ca}${exe}"
            url="https://github.com/docker/buildx/releases/download/v${buildx_ver}/buildx-v${buildx_ver}.${os}-${ba}${exe}"
            mirror_download "$url" "$mirror_dir/docker/buildx/releases/download/v${buildx_ver}/buildx-v${buildx_ver}.${os}-${ba}${exe}"
        done
    done

    mirror_write_latest compose "$compose_ver"
    mirror_write_latest buildx "$buildx_ver"
}

## fzf 二进制，保留 GitHub releases 目录结构 fzf/releases/download/v<ver>/
mirror_fzf() {
    local ver
    ver="$(mirror_resolve_latest junegunn/fzf || true)"
    [ -n "$ver" ] || {
        msg warn "resolve fzf latest failed, skip"
        return
    }
    msg cyan "fzf v${ver}"
    for ca in x86_64 aarch64; do
        local ba
        ba=$(sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/' <<<"$ca")
        mirror_download "https://github.com/junegunn/fzf/releases/download/v${ver}/fzf-${ver}-linux_${ba}.tar.gz" \
            "$mirror_dir/fzf/releases/download/v${ver}/fzf-${ver}-linux_${ba}.tar.gz"
    done
    mirror_write_latest fzf "$ver"
}

## laradock 运行时镜像：镜像名从 compose 文件解析（MIRROR 已展开成完整名），
## 按架构 pull 后 docker save 成 tgz 上传 CDN，目标机 docker load -i 即可用，
## 绕开阿里云镜像仓库限速与 Docker Hub 连通问题。
## 目录结构 d/images/<arch>/<镜像名转译>.tgz
mirror_images() {
    [ -d "$g_laradock_path" ] || {
        msg warn "skip images: no $g_laradock_path"
        return
    }
    command -v docker >/dev/null 2>&1 || {
        msg warn "skip images: no docker on this host"
        return
    }
    local images img arch ba out_file pulled
    if [ -n "${arg_mirror_name:-}" ]; then
        images=("$arg_mirror_name")
    else
        mapfile -t images < <(
            (cd "$g_laradock_path" && docker compose config 2>/dev/null) |
                awk '/^[[:space:]]+image:/' |
                sed -E 's/^[[:space:]]+image:[[:space:]]*//; s/"//g; s/^.[[:space:]]*$//' |
                sort -u
        )
    fi
    [ "${#images[@]}" -gt 0 ] || {
        msg warn "no images resolved from compose, skip"
        return
    }

    for arch in x86_64 aarch64; do
        ba=$(sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/' <<<"$arch")
        out_file="$mirror_dir/images/${arch}/runtime-images.tgz"
        mkdir -p "$(dirname "$out_file")"
        pulled=()
        for img in "${images[@]}"; do
            msg cyan "images: pull ${img} (${arch})"
            if docker pull --platform "linux/${ba}" "$img" >/dev/null 2>&1; then
                pulled+=("$img")
            else
                msg warn "docker pull failed (skip): ${img} (${arch})"
            fi
        done
        if [ "${#pulled[@]}" -gt 0 ]; then
            if docker save "${pulled[@]}" | gzip >"$out_file" 2>/dev/null; then
                mirror_upload "$out_file"
            else
                msg warn "docker save failed: runtime images (${arch})"
            fi
        else
            msg warn "no images pulled for ${arch}, skip save"
        fi
    done
}

## 更新/新增 latest.txt 中某个 key 的值（格式 KEY=version，供 fly.sh 离线取版本号）
mirror_write_latest() {
    local key="$1" ver="$2" latest="$mirror_dir/latest.txt"
    mkdir -p "$(dirname "$latest")"
    if [ -f "$latest" ] && grep -q "^${key}=" "$latest"; then
        sed -i.bak "s|^${key}=.*|${key}=${ver}|" "$latest" && rm -f "$latest.bak"
    else
        echo "${key}=${ver}" >>"$latest"
    fi
    mirror_upload "$latest"
}

## 镜像 Docker 相关文件到本地 d/ 目录（结构与官网一致），并上传到 OSS bucket
## 用法: ./fly.sh mirror <bucket>
mirror_docker() {
    mirror_dir="d"
    mirror_endpoint="oss-cn-hangzhou-internal.aliyuncs.com"
    mirror_os="linux"
    mirror_docker_versions="29.7.1 28.5.2"

    local kind
    kind="${arg_mirror_kind:-all}"

    msg step "Mirror docker files to oss://$arg_mirror_bucket/$mirror_dir/ (kind: ${kind})"

    case "$kind" in
    ## 无参数=全量；否则按 kind 只镜像某类。
    ## get-docker: 官方安装脚本; docker: 静态二进制 tgz; plugins: compose/buildx; fzf: fzf 二进制; images: laradock 运行时镜像
    all)
        mirror_download "https://get.docker.com" "$mirror_dir/get-docker.sh"
        mirror_docker_static
        mirror_plugins
        mirror_fzf
        mirror_images
        ;;
    get-docker)
        mirror_download "https://get.docker.com" "$mirror_dir/get-docker.sh"
        ;;
    docker)
        mirror_docker_static
        ;;
    plugins)
        mirror_plugins
        ;;
    fzf)
        mirror_fzf
        ;;
    images)
        mirror_images
        ;;
    *)
        msg warn "unknown mirror kind: '$kind' (all|get-docker|docker|plugins|fzf|images)"
        return 1
        ;;
    esac

    msg green "done. mirror dir: $mirror_dir (kind: ${kind})"
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
    if [[ "${OS[id]}" == *kylin* ]] && [[ "${OS[arch]}" =~ aarch64|arm64 ]]; then
        docker_ver=28.5.2
        compose_ver=v2.40.3
    else
        docker_ver=29.7.1
        compose_ver=v5.4.0
    fi
    docker_arch="${OS[docker]}"
    plugin_arch="${OS[plugin]}"
    compose_arch="${OS[compose]}"
    $g_curl_opt "$(docker_static_src "$docker_arch" "docker-${docker_ver}.tgz")" -o "$offline_dir/docker-${docker_ver}.tgz"
    $g_curl_opt "$(docker_static_src "$docker_arch" "docker-rootless-extras-${docker_ver}.tgz")" -o "$offline_dir/docker-rootless-extras-${docker_ver}.tgz"
    # compose 固定版本离线包：中国环境优先 CDN 镜像，失败回退 GitHub
    if "${IS_CHINA}"; then
        $g_curl_opt "$g_url_fly_cdn/docker/compose/releases/download/${compose_ver}/docker-compose-linux-${compose_arch}" -o "$offline_dir/docker-compose" ||
            $g_curl_opt "https://github.com/docker/compose/releases/download/${compose_ver}/docker-compose-linux-${compose_arch}" -o "$offline_dir/docker-compose"
    else
        $g_curl_opt "https://github.com/docker/compose/releases/download/${compose_ver}/docker-compose-linux-${compose_arch}" -o "$offline_dir/docker-compose"
    fi
    download_plugin "$offline_dir/docker-buildx" "$plugin_arch" buildx

    # 按 compose 中定义的真实镜像名，整批 save 成单个归档（load 时也一次载入）
    # compose 的 images 只支持 table/json，用默认 table 解析
    msg time "Save Laradock runtime images into a single archive"
    local img_archive runtime_images
    img_archive="$offline_dir/runtime-images.tgz"
    mapfile -t runtime_images < <(
        (cd "$g_laradock_path" && docker compose images 2>/dev/null) |
            awk 'NR>1 {print $2 ":" $3}' | sed '/<none>/d' | sort -u
    )
    if [ "${#runtime_images[@]}" -gt 0 ]; then
        docker save "${runtime_images[@]}" | gzip >"$img_archive" 2>/dev/null ||
            msg warn "docker save failed for runtime images"
    else
        msg warn "no runtime images resolved from compose, skip save"
    fi

    write_docker_service "$offline_dir/docker.service"

    ## 离线=零网络，单个归档自带整套环境：打包两个目录 —— docker/ 与 DATA_PATH_HOST 数据目录（默认 ~/.laradock/data）。
    ## 以 docker 父目录为 -C：docker/ 与其下成员全用相对名，任意位置解压都保持同级
    ## （解压到家目录即等于原位还原）；data 不在父目录下（不相交盘）才回退绝对成员，用 sudo tar -xzf -C / 还原。
    ## .env 里绝对的是 APP_CODE_PATH_HOST（fly.sh 每次运行按安装位置重写，解压后跑一次收敛）。
    msg time "Compress offline roots into a single archive"
    local docker_dir data_dir base rel_data archive members
    docker_dir="$(dirname "$g_laradock_path")"
    data_dir=$(awk -F= '/^DATA_PATH_HOST=/{print $2; exit}' "$g_laradock_env" 2>/dev/null)
    ## .env 里默认是 ~/ 相对（~/.laradock/data），必须展开成绝对路径才能命中 -d 判断
    data_dir="${data_dir/#\~/$HOME}"
    base="$(dirname "$docker_dir")"
    archive="$base/offline.tgz"
    members=("$(basename "$docker_dir")")
    rel_data="${data_dir#"$base"/}"
    if [[ -d "$data_dir" ]]; then
        if [[ "$rel_data" != "$data_dir" ]]; then
            ## data 在 docker 父目录之下：与 docker 同一 -C 用相对名
            members+=("$rel_data")
        else
            ## 不相交盘：data 用绝对成员（tar 自动去掉带头斜杠）
            members+=("$data_dir")
        fi
    fi

    if tar -czf "$archive" -C "$base" --exclude='*/laradock/.git' "${members[@]}"; then
        msg green "Offline archive: $archive"
    else
        rm -f "$archive"
        msg warn "Compress offline package FAILED, skip archive"
    fi

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

    # 单归档：整批镜像一次载入
    # shellcheck disable=SC2086 # use_sudo 必须裸写：root 时为空、否则为 sudo，靠空白分词
    [ -f "$offline_dir/runtime-images.tgz" ] && $use_sudo docker load -i "$offline_dir/runtime-images.tgz"

    cd "$g_laradock_path" || exit 1
    docker compose up -d --no-build redis mysql php-fpm spring nginx
}

handle_ssl_config() {
    # 把用户已有的 nginx SSL 文件导入 nginx/ssl/default.{key,pem}
    # 裸 key/crt/pem 直接复制；zip/gz/tgz/xz 先解压再复制
    local ssl_dir="$g_laradock_path/nginx/ssl" f temp_dir
    mkdir -p "$ssl_dir"
    temp_dir=$(mktemp -d)

    # 1. 解压归档文件(zip/gz/tgz/xz)到临时目录，不改动原文件
    find "$HOME" "/tmp" -maxdepth 1 -type f \
        \( -iname "*.zip" -o -iname "*.gz" -o -iname "*.tgz" -o -iname "*.xz" \) 2>/dev/null |
        while read -r f; do
            case "$f" in
            *.tar.gz | *.tgz) tar -xzf "$f" -C "$temp_dir" 2>/dev/null || true ;;
            *.tar.xz) tar -xJf "$f" -C "$temp_dir" 2>/dev/null || true ;;
            *.zip) unzip -joq "$f" -d "$temp_dir" || true ;;
            *.gz) gunzip -c "$f" >"$temp_dir/$(basename "${f%.gz}")" 2>/dev/null || true ;;
            *.xz) unxz -c "$f" >"$temp_dir/$(basename "${f%.xz}")" 2>/dev/null || true ;;
            esac
        done

    # 2. 遍历散落及解压出的 key/crt/pem，按内容甄别后装入 default.{key,pem}
    {
        find "$HOME" "/tmp" -maxdepth 1 -type f \
            \( -iname "*.key" -o -iname "*.crt" -o -iname "*.pem" -o -iname "*.private" -o -iname "*.priv" \) 2>/dev/null
        find "$temp_dir" -type f \
            \( -iname "*.key" -o -iname "*.crt" -o -iname "*.pem" -o -iname "*.private" -o -iname "*.priv" \) 2>/dev/null
    } | while read -r f; do
        case "$f" in
        "$ssl_dir"/*) continue ;;
        esac
        if [[ "$f" == *.crt ]] || openssl x509 -noout -in "$f" 2>/dev/null; then
            msg time "导入证书 $f -> default.pem"
            cp -f "$f" "$ssl_dir/default.pem"
            chmod 644 "$ssl_dir/default.pem"
        elif [[ "$f" == *.key || "$f" == *.private || "$f" == *.priv ]] || openssl pkey -noout -in "$f" 2>/dev/null; then
            msg time "导入私钥 $f -> default.key"
            cp -f "$f" "$ssl_dir/default.key"
            chmod 600 "$ssl_dir/default.key"
        fi
    done

    # 3. 打印证书有效期(仅打印实际存在的文件)
    for p in "$ssl_dir"/*.pem "$ssl_dir"/*.crt; do
        [ -f "$p" ] || continue
        openssl x509 -noout -dates -in "$p" 2>/dev/null || continue
    done

    # 4. nginx 在跑则 reload，不在则跳过(用户稍后 ./fly.sh nginx)
    if dco ps --services --filter status=running 2>/dev/null | grep -xq nginx; then
        reload_nginx
    else
        msg yellow "nginx 未运行，跳过 reload；启动 nginx 后会生效"
    fi
    rm -rf "$temp_dir"
}

install_acme() {
    install_acme_official
    local acme_home="$HOME/.acme.sh"

    local key="$g_laradock_path/nginx/ssl/default.key"
    local pem="$g_laradock_path/nginx/ssl/default.pem"

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
        openssl x509 -noout -dates -in "$p"
    done
}

## 从 CDN 下载某服务对应的镜像 tgz 并 docker load（镜像名取 compose 对该服务解析出的 image）
## 归档约定：d/images/<arch>/<镜像名: /: 转译__.tgz>，与 mirror_images 的产物一致
cdn_load_service_image() {
    local svc="$1" img tgz target tmp
    img=$(cd "$g_laradock_path" && docker compose config 2>/dev/null |
        awk -v svc="^  ${svc}:" '$0 ~ svc {f=1;next} f && /^    image:/ {sub(/^    image:[[:space:]]*/,""); gsub(/"/,""); print; exit} f && !/^[[:space:]]/ {f=0}')
    [ -n "$img" ] || {
        msg warn "cdn load: no image for service [$svc], skip"
        return
    }
    tgz="$(echo "$img" | tr '/:' '__').tgz"
    target="$g_url_fly_cdn/images/${OS[docker]}/$tgz"
    msg cyan "cdn load: $img <- $target"
    tmp="${TMPDIR:-/tmp}/fly-cdn-load.$$.tgz"
    if $g_curl_opt "$target" -o "$tmp" &&
        docker load -q -i "$tmp" >/dev/null 2>&1 &&
        docker image inspect "$img" >/dev/null 2>&1; then
        msg green "cdn load ok: $img"
    else
        msg warn "cdn load failed (service [$svc] 走正常 pull/重试): $img"
    fi
    rm -f "$tmp"
}

docker_service() {
    [ "${#args[@]}" -eq 0 ] && {
        msg warn "no arguments for docker service"
        return 0
    }

    msg step "Start docker services (via ./laradock)..."
    if "${arg_use_cdn_images:-false}"; then
        msg cyan "cdn-images 模式：先用 CDN tgz docker load，绕开仓库 pull/限速"
    else
        msg cyan "如需拉取镜像（pull image），可能需要几分钟，请耐心等待..."
    fi
    local rc arg idx sleep_s failed="" img_local=false
    # 阿里云镜像仓库有速率限制：逐个服务启动，间隔随机 10-20 秒；单个服务失败最多重试 1 次
    for ((idx = 0; idx < ${#args[@]}; idx++)); do
        arg=${args[$idx]}
        ## 镜像已在本地（docker compose images 只列本地已存在的镜像）→ cdn load 和限速 sleep 都跳过
        img_local=false
        dco images "$arg" 2>/dev/null | tail -n +2 | grep -q . && img_local=true
        ${arg_use_cdn_images:-false} && ! $img_local && cdn_load_service_image "$arg"
        for ((try = 1; try <= 2; try++)); do
            msg cyan "[$((idx + 1))/${#args[@]}] start $arg (try $try) ..."
            dco up -d "$arg" --quiet-pull
            rc=$?
            if [ $rc -eq 0 ] || [ $try -eq 2 ]; then
                break
            fi
            msg warn "service [$arg] start failed, retry after random wait..."
            sleep_s=$((RANDOM % 16 + 5))
            msg cyan "wait ${sleep_s}s before retry..."
            sleep "$sleep_s"
        done
        if [ $rc -ne 0 ]; then
            msg red "service [$arg] start failed"
            failed="$failed $arg"
        fi
        # 起下一个前随机等 10-20 秒（镜像已存在时 sleep=0，重复 run 不空等）
        if [ $idx -lt $((${#args[@]} - 1)) ] && [ $rc -eq 0 ] && ! $img_local; then
            sleep_s=$((RANDOM % 16 + 5))
            msg cyan "wait ${sleep_s}s before next service..."
            sleep "$sleep_s"
        fi
    done
    if [ -n "$failed" ]; then
        msg red "docker service start failed:$failed"
        return 1
    fi

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
    echo "INDEX Page: $(date)" | $use_sudo tee "$g_laradock_html/index.html" || true

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
    v=$(grep -m1 "^${key}=" "$g_laradock_env" 2>/dev/null | sed 's/^[^=]*=//; s/ *# set by laradock.*//') || true
    if [[ -z "$v" ]]; then
        v_default=$(grep -h "^${key}=" "$g_laradock_path"/*/defaults.env 2>/dev/null | head -1 | cut -d= -f2-) || true
        v="${v_default:-$(grep -m1 "^${key}=" "$g_laradock_path/.env.example" 2>/dev/null | sed 's/^[^=]*=//; s/ *# set by laradock.*//')}" || true
    fi
    printf '%s' "$v"
}

# 服务器本机集成环境信息（本地实现：只输出 key=value，空行分类，不动官方 laradock）
get_env_info() {
    echo "####  客户若没有独立 redis/mysql，使用以下mysql/redis连接信息"
    echo "####  客户若已有独立 redis/mysql，直接用独立的 host/port/user/pass 连接即可，忽略下列信息"
    echo "####  代码内始终用标准端口连接：redis:6379/mysql:3306"
    echo "####  下列端口仅用于 SSH 端口转发映射（可能不同于标准端口）"
    echo
    local nginx_ver
    ## 从容器读实际 nginx 版本（nginx -v 输出到 stderr）；容器没起/没装则回退占位
    nginx_ver="$(dco exec -T nginx nginx -v 2>&1 | sed -nE 's/^nginx version: nginx\/([0-9.]+).*/\1/p' | head -1)" || true
    [[ -z "$nginx_ver" ]] && nginx_ver="unknown"
    echo "NGINX_VERSION=$nginx_ver"
    echo "NGINX_HOST_HTTP_PORT=$(env_of NGINX_HOST_HTTP_PORT)"
    echo "NGINX_HOST_HTTPS_PORT=$(env_of NGINX_HOST_HTTPS_PORT)"
    echo

    echo "PHP_VERSION=$(env_of PHP_VERSION)"
    echo

    echo "MYSQL_VERSION=$(env_of MYSQL_VERSION)"
    echo "MYSQL_HOST=mysql"
    echo "MYSQL_PORT=$(env_of MYSQL_PORT)"
    echo "MYSQL_DATABASE=$(env_of MYSQL_DATABASE)"
    echo "MYSQL_USER=$(env_of MYSQL_USER)"
    echo "MYSQL_PASSWORD=$(env_of MYSQL_PASSWORD)"
    echo

    echo "REDIS_VERSION=$(env_of REDIS_VERSION)"
    echo "REDIS_HOST=redis"
    echo "REDIS_PORT=$(env_of REDIS_PORT)"
    echo "REDIS_PASSWORD=$(env_of REDIS_PASSWORD)"
    echo

    echo "JDK_VERSION=$(env_of SPRING_JDK_VERSION)"
    echo
    echo "NODE_VERSION=$(env_of NODE_VERSION)"
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
    local data_path stamp
    data_path=$(awk -F= '/^DATA_PATH_HOST=/{print $2; exit}' "$g_laradock_env" 2>/dev/null)
    data_path="${data_path:-~/.laradock/data}"
    data_path="${data_path/#\~/$HOME}"
    stamp="$(date +%Y%m%d%H%M%S)"
    for d in "$g_laradock_path" "$data_path"; do
        # 只防精确的根目录/家目录本身，家目录下的常规安装路径（$HOME/docker/...）不拦
        case "$d" in
        /)
            msg red "Refuse to touch / for safety, skip: $d"
            ;;
        "$HOME")
            msg red "Refuse to touch \$HOME for safety, skip: $d"
            ;;
        *)
            $use_sudo mv "$d" "$d.bak-$stamp"
            msg time "Moved $d -> $d.bak-$stamp"
            ;;
        esac
    done
}

# 切换单个服务版本并重启（只写 .env + docker compose up，不重装/不 rebuild）
# 用法: ./fly.sh switch <mysql|php|java|node> <ver>
switch_service() {
    local svc="${arg_switch_svc:?Usage: ./fly.sh switch <mysql|php|java|node> <ver>}"
    local ver="${arg_switch_ver:?Usage: ./fly.sh switch <mysql|php|java|node> <ver>}"
    local compose_svc key
    case "$svc" in
    mysql) compose_svc=mysql key=MYSQL_VERSION ;;
    php) compose_svc=php-fpm key=PHP_VERSION ;;
    java | spring) compose_svc=spring key=SPRING_JDK_VERSION ;;
    node | nodejs) compose_svc=nodejs key=NODE_VERSION ;;
    *)
        msg error "unknown service: $svc (mysql|php|java|node)"
        return 1
        ;;
    esac
    msg step "Switch $svc to version $ver"
    dco set "$key=$ver"
    dco up -d "$compose_svc" --quiet-pull
}

# 单版本多实例：给 spring/nodejs 追加一个完整 compose 服务块到 multi/compose.yml
# （完整复制、不用 extends，避免继承的 ports 合并冲突），并创建应用目录。
# 用法: ./fly.sh add <spring|nodejs> <name> [ver] [host_port]
#   name     服务名，如 spring-17a / nodejs-20a（同时是 www 下的应用目录名）
#   ver      版本，默认 spring=17 / nodejs=20
#   host_port 可选宿主端口；省略则不映射端口（仅容器网络互访）。
#             spring 映射 <port>:8080 和 <port+1>:8081；nodejs 映射 <port>:8080
add_service_instance() {
    local svc="${arg_add_svc:?Usage: ./fly.sh add <spring|nodejs> <name> [ver] [host_port]}"
    local name="${arg_add_name:?Usage: ./fly.sh add <spring|nodejs> <name> [ver] [host_port]}"
    local ver="${arg_add_ver:-}" host_port="${arg_add_port:-}"
    local multi_file="$g_laradock_path/multi/compose.yml"
    local block ports_yaml=""

    case "$svc" in
    spring | java)
        ver="${ver:-17}"
        ;;
    nodejs | node)
        ver="${ver:-20}"
        ;;
    *)
        msg error "unknown service: $svc (spring|nodejs)"
        return 1
        ;;
    esac

    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        msg error "invalid service name: $name"
        return 1
    fi
    if grep -q "^    ${name}:" "$multi_file" 2>/dev/null; then
        msg warn "service [$name] already exists in $multi_file, skip"
        return 0
    fi

    if [ -n "$host_port" ]; then
        if [[ ! "$host_port" =~ ^[0-9]+$ ]]; then
            msg error "host_port must be a number: $host_port"
            return 1
        fi
        if [[ "$svc" == spring || "$svc" == java ]]; then
            ports_yaml="      ports:
        - \"${host_port}:8080\"
        - \"$((host_port + 1)):8081\""
        else
            ports_yaml="      ports:
        - \"${host_port}:8080\""
        fi
    fi

    if [[ "$svc" == spring || "$svc" == java ]]; then
        block="    ${name}:
      image: \${MIRROR}amazoncorretto:${ver}-base
      build:
        context: ../spring
        args:
          - SPRING_JDK_VERSION=${ver}
      environment:
        - JAVA_OPTS=\${SPRING_JAVA_OPTS}
        - SPRING_WORKDIR=\${SPRING_WORKDIR}
        - SPRING_APP_DIR=${name}
        - SPRING_JAR=\${SPRING_JAR}
        - SPRING_AUTO_DETECT=\${SPRING_AUTO_DETECT}
      working_dir: \${SPRING_WORKDIR}
${ports_yaml}
      volumes:
        - \${APP_CODE_PATH_HOST}/${name}:\${SPRING_WORKDIR}\${APP_CODE_CONTAINER_FLAG}
      networks:
        - frontend
        - backend"
    else
        block="    ${name}:
      image: \${MIRROR}node:${ver}-base
      build:
        context: ../nodejs
        args:
          - NODE_VERSION=${ver}
      environment:
        - NODE_VERSION=${ver}
${ports_yaml}
      volumes:
        - \${APP_CODE_PATH_HOST}/${name}:/app
      networks:
        - frontend
        - backend"
    fi

    msg step "Add service [$name] ($svc v${ver}) to multi/compose.yml"
    printf '\n%s\n' "$block" >>"$multi_file"

    # 应用目录：spring/nodejs 容器内 uid=1000
    mkdir -p "$g_www_root/$name"
    ${use_sudo:-} chown -R 1000:1000 "$g_www_root/$name" 2>/dev/null || true

    msg time "App dir created: $g_www_root/$name"
    msg time "Now: ./fly.sh rebuild $name  或直接 ./laradock up -d $name"
    write_nginx_inc "$name" "$svc"
}

# 生成单实例 nginx 站点配置 <name>.inc 到 nginx/sites/（挂载为 /etc/nginx/conf.d，
# 由 default.conf 的 include conf.d/*.inc; 自动引入）。已存在则跳过，不覆盖手动修改。
write_nginx_inc() {
    local name="$1" svc="$2"
    local inc_file="$g_laradock_path/nginx/sites/${name}.inc"
    [ -d "$(dirname "$inc_file")" ] || {
        msg warn "no $(dirname "$inc_file") directory, skip nginx inc"
        return 0
    }
    if [ -f "$inc_file" ]; then
        msg warn "nginx inc exists, skip: $inc_file"
        return 0
    fi
    case "$svc" in
    spring | java)
        cat >"$inc_file" <<EOF
## ${name}
location /${name} {
    proxy_pass http://${name}:8080;
}
location /${name}-ui {
    proxy_pass http://${name}:8081;
}
EOF
        ;;
    nodejs | node)
        cat >"$inc_file" <<EOF
## ${name}
location /${name} {
    proxy_pass http://${name}:8080;
}
EOF
        ;;
    *)
        msg warn "unknown service [$svc], skip nginx inc"
        return 0
        ;;
    esac
    msg time "nginx inc generated: $inc_file"
    reload_nginx
}

# 扫描 multi/compose.yml 中所有 spring-*/nodejs-* 服务，为缺失的生成 <name>.inc。
# 用法: ./fly.sh nginx-gen
nginx_inc_gen() {
    local multi_file="$g_laradock_path/multi/compose.yml"
    local running name svc kind
    # 优先只对正在运行的服务生成（docker compose ps --status running），
    # docker 不可用时回退到扫描 multi/compose.yml 中所有 spring-*/nodejs-* 定义。
    running=$(dco ps --services --status running 2>/dev/null | grep -E '^(spring|nodejs)-' || true)
    if [ -n "$running" ]; then
        while read -r name; do
            [ -n "$name" ] || continue
            if grep -qE "^\s+${name}:" "$multi_file" 2>/dev/null; then
                kind=$(awk -v n="$name" '
                    $0 ~ "^    " n ":" {inblock=1; next}
                    inblock && /^[^ ]/ {inblock=0}
                    inblock && kind == "" {
                        if ($0 ~ /\.\.\/spring/ || $0 ~ /amazoncorretto/) kind="spring"
                        else if ($0 ~ /\.\.\/nodejs/) kind="nodejs"
                    }
                    END {print kind}
                ' "$multi_file")
            else
                # 未定义在 multi/compose.yml（如默认 spring/nodejs 服务），按名推断
                case "$name" in
                nodejs*) kind=nodejs ;;
                spring*) kind=spring ;;
                *) continue ;;
                esac
            fi
            [ -n "$kind" ] && write_nginx_inc "$name" "$kind"
        done <<<"$running"
        return 0
    fi

    # docker 不可用：扫描配置中全部 spring-*/nodejs-* 服务
    [ -f "$multi_file" ] || {
        msg warn "no $multi_file, skip"
        return 0
    }
    while read -r name kind; do
        [ -n "$name" ] || continue
        write_nginx_inc "$name" "$kind"
    done < <(awk '
        /^    [a-z0-9][a-z0-9_-]*:$/ {
            if (name != "" && (name ~ /^spring-/ || name ~ /^nodejs-/)) print name, kind
            name = $0; sub(/:$/, "", name); sub(/^[[:space:]]*/, "", name)
            kind = ""
            inblock = 1
            next
        }
        inblock && kind == "" {
            if ($0 ~ /\.\.\/spring/ || $0 ~ /amazoncorretto/) kind = "spring"
            else if ($0 ~ /\.\.\/nodejs/) kind = "nodejs"
        }
        END {
            if (name != "" && (name ~ /^spring-/ || name ~ /^nodejs-/)) print name, kind
        }
    ' "$multi_file")
}

print_usage() {
    cat <<EOF
Usage: $0 [parameters ...]

Install services (default versions: mysql 8.0 / java 17 / php 8.1 / node 20):
    mysql [mysql-<ver>]     Install MySQL (alias: mysql-8.0, mysql-5.7 ...).
    java [java-<ver>]       Install OpenJDK (aliases: java-8, jdk, spring ...).
    php [php-<ver>]         Install php-fpm (aliases: php-8.1, fpm ...).
    node [node-<ver>]       Install Node.js (aliases: node-22, nodejs ...).
    redis                   Install Redis.
    nginx                   Install nginx.
    gitlab                  Install GitLab (alias: git).

Management:
    info                    Print MySQL/Redis connection info (via ./laradock info).
    mysql-cli [user]        Exec into MySQL CLI (./laradock db).
    redis-cli               Exec into Redis CLI (./laradock enter redis).
    test                    Smoke-test nginx + php-fpm.
    reset                   Reset/remove laradock (aliases: clean, clear; backs up to .bak-<ts>).

Standalone components:
    zsh                     Install zsh/fzf/oh-my-zsh/byobu.
    lsync                   Install and setup lsyncd.
    wg                      Install wireguard.
    trzsz                   Install trzsz.
    acme [domain]           Install acme.sh (e.g. api.example.com).
    ssl                     Copy SSL key files to nginx/ssl.
    select [mysql|php|java|node]
                            Interactively select service and version with fzf.
    offline-prepare         Prepare offline packages and docker image tars; bundle docker/ + data_dir/ into offline.tar.gz (zero-network).
    offline-install         Install Docker and Laradock offline.
    mirror <bucket>         Mirror docker files (get-docker.sh / static tgz / compose / buildx / fzf / runtime images) to OSS.
    switch <svc> <ver>      Switch one service's version and restart (mysql|php|java|node).
    add <spring|nodejs> <name> [ver] [host_port]
                            Add one more instance of the same version to multi/compose.yml
                            (e.g. ./fly.sh add spring spring-17a 17 8082; omit host_port to skip host port mapping).
    nginx-gen               Generate missing <name>.inc for every spring-*/nodejs-* service
                            in multi/compose.yml (auto-included by conf.d/*.inc).

Options:
    cdn-images (also cdn)   With a service install/start: load runtime image tgz from
                            CDN (docker load, bypass registry pull/rate limit) before start.
    not-china (also not-cn, ncn, github)
                            Use GitHub/official sources instead of China mirrors.
    install-docker-without-aliyun
                            Same as docker.
    -h, --help              Show this help message.
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
            [[ "${1}" == *-[0-9]* ]] && g_java_ver=${1##*-}
            ;;
        php | fpm | fpm-[0-9]* | php-[0-9]* | php-fpm-[0-9]*)
            args+=(php-fpm)
            [[ "${1}" == *-[0-9]* ]] && g_php_ver=${1##*-}
            ;;
        node | nodejs | node-[0-9]* | nodejs-[0-9]*)
            args+=(nodejs)
            [[ "${1}" == *-[0-9]* ]] && g_node_ver=${1##*-}
            ;;
        nginx)
            args+=(nginx)
            ;;
        cdn-images | cdn)
            # 用 CDN 上镜像好的 tgz（docker load）绕开仓库 pull；与 redis/mysql/php 等服务参数组合使用
            arg_use_cdn_images=true
            ;;
        gitlab | git)
            args+=(gitlab)
            ;;
        not-china | not-cn | ncn | github)
            IS_CHINA=false
            ;;
        install-docker-without-aliyun)
            # 无参数等价 auto：默认流程本就安装 docker（get.docker.com 中国环境自带阿里云镜像）
            ;;
        zsh | install-zsh)
            RUN+=(ensure_base_dependence install_zsh)
            auto_mode=false
            ;;
        acme | install-acme)
            RUN+=(install_acme)
            auto_mode=false
            [ -n "$2" ] && shift
            ;;
        trzsz | install-trzsz)
            RUN+=(install_trzsz)
            auto_mode=false
            ;;
        lsync | lsyncd | install-lsyncd)
            RUN+=(install_lsyncd)
            auto_mode=false
            ;;
        wg | wireguard | install-wg)
            RUN+=(install_wg)
            auto_mode=false
            ;;
        offline-prepare | prepare-offline)
            RUN+=(prepare_offline)
            auto_mode=false
            [ -n "$2" ] && shift
            ;;
        offline-install | install-offline)
            RUN+=(install_offline)
            auto_mode=false
            ;;
        mirror)
            RUN+=(mirror_docker)
            arg_mirror_bucket="$2"
            arg_mirror_kind="${3:-all}"
            arg_mirror_name="${4:-}"
            auto_mode=false
            [ -n "$2" ] && shift
            [ -n "$2" ] && shift
            [ -n "$2" ] && shift
            ;;
        switch)
            arg_switch_svc="$2"
            arg_switch_ver="$3"
            RUN+=(switch_service)
            auto_mode=false
            [ -n "$2" ] && shift
            [ -n "$2" ] && shift
            ;;
        add)
            arg_add_svc="$2"
            arg_add_name="$3"
            arg_add_ver="$4"
            arg_add_port="$5"
            RUN+=(add_service_instance)
            auto_mode=false
            [ -n "$2" ] && shift
            [ -n "$2" ] && shift
            [ -n "$2" ] && shift
            [ -n "$2" ] && shift
            ;;
        nginx-gen)
            RUN+=(nginx_inc_gen)
            auto_mode=false
            ;;
        info)
            RUN+=(get_env_info)
            auto_mode=false
            ;;
        mysql-cli)
            RUN+=(check_docker mysql_shell)
            auto_mode=false
            [ -z "$2" ] || shift
            ;;
        redis-cli)
            RUN+=(check_docker redis_shell)
            auto_mode=false
            ;;
        test)
            RUN+=(ensure_base_dependence check_docker check_laradock check_laradock_env docker_service check_nginx check_php_fpm check_spring)
            auto_mode=false
            ;;
        reset | clean | clear)
            RUN+=(reset_laradock)
            auto_mode=false
            ;;
        ssl)
            RUN+=(handle_ssl_config)
            auto_mode=false
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

            # 根据选择的组件设置安装参数
            case "$service" in
            mysql) args=(mysql) ;;
            php) args=(php-fpm) ;;
            java) args=(spring) ;;
            node) args=(nodejs) ;;
            esac
            RUN+=(ensure_base_dependence check_docker check_laradock check_laradock_env docker_service)
            ;;
        *)
            print_usage
            ;;
        esac
        shift
    done

    # auto mode: 无参数默认全流程
    if [ "${auto_mode:-true}" = true ]; then
        if [ ${#args[@]} -eq 0 ]; then
            args+=(redis mysql php-fpm spring nginx)
            msg warn "EN: Using default args: [${args[*]}]"
            msg warn "CN: 没有提供任何参数，将使用默认参数: [${args[*]}]"
        fi
        RUN+=(ensure_base_dependence check_docker check_laradock check_laradock_env docker_service check_nginx check_php_fpm check_spring)
    fi
    [ "${args[*]}" ] && echo "The final args: ${args[*]}"

    g_php_ver=${g_php_ver:-8.1}
    g_java_ver=${g_java_ver:-17}
    g_mysql_ver=${g_mysql_ver:-8.0}
    g_mysql_db=${g_mysql_db:-defaultdb}
    g_mysql_user=${g_mysql_user:-defaultdb}
    g_node_ver=${g_node_ver:-20}

}

main() {
    SECONDS=0
    set -Eeo pipefail

    IS_CHINA=${IS_CHINA:-true}

    parse_command_args "$@"

    ## global variables g_* / 全局变量
    g_me_path="$(dirname "$(readlink -f "$0")")"

    g_curl_opt='curl --connect-timeout 10 -fL'
    g_url_fly_cdn="https://cdn.flyh5.cn/d"
    g_url_fly_ico="$g_url_fly_cdn/flyh6.ico"

    if "${IS_CHINA}"; then
        g_url_laradock_git=https://gitee.com/xiagw/laradock.git
        g_url_laradock_archive=https://gitee.com/xiagw/laradock/repository/archive/main.tar.gz
        g_url_keys="$g_url_fly_cdn/xiagw.keys"
        g_sha_keys='e0cba5045051f1aef66f9696aa7a25e52c023e8cfbf1d4fb9aa6dc59c64bdefe'
        g_url_fzf="https://gitee.com/mirrors/fzf.git"
        g_url_ohmyzsh="https://gitee.com/mirrors/ohmyzsh.git"
    else
        g_url_laradock_git=https://github.com/xiagw/laradock.git
        g_url_laradock_archive=https://codeload.github.com/xiagw/laradock/tar.gz/refs/heads/main
        g_url_keys='https://github.com/xiagw.keys'
        g_sha_keys='73996ee473eecd97199748358771d3e2241faa5c29b29f3aeb441e850d495356'
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
    g_www_root="$(dirname "$g_laradock_path")"/www
    g_laradock_html="$g_www_root"/html

    ## 一次性检测 root 权限 (整个文件只 check root 一次)
    ## 三种情况: root / 非root有sudo / 非root无sudo
    ## is_root 只表示"真的是 root"（check_root 对 sudo 用户也返回成功）
    check_root || true

    ## 统一探测发行版/版本/架构一次，存入全局关联数组 OS，后续各处按需取用
    detect_os_info

    ## 按 parse_command_args 决定的 RUN 数组顺序执行（每个命令显式列出所需的函数序列）
    for fn in "${RUN[@]}"; do
        "$fn"
    done

    echo "END"
}

main "$@"
