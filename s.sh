#!/usr/bin/env bash
# s.sh - Manage ~/.ssh/config entries (add/update/remove/list/show/connect)
# Implements CRUD for Host entries using marked blocks so the script can safely
# add, update and remove entries it manages.
# Supports IdentityFile, Port, User, HostName, LocalForward, RemoteForward, ProxyJump
# Interactive selection for operations via fzf when available.

set -euo pipefail

SSH_CONFIG="${S_SH_CONFIG:-$HOME/.ssh/config2}"
BACKUP_DIR="$HOME/.ssh/s.sh-backups"
MARK_PREFIX="# >>> s.sh-managed:"
MARK_SUFFIX="# <<< s.sh-managed:"

show_help() {
    cat <<'EOF'
Usage: s.sh <command> [options]

Commands:
  add NAME [--host HOSTNAME] [--user USER] [--port PORT] [--identity FILE]
                [--local-forward L:host:port] [--remote-forward R:host:port]
                [--proxyjump JUMP]
  update NAME [same options as add]   Update an existing managed entry (or create)
  remove NAME                         Remove a managed entry (uses fzf if no NAME)
  list                                List managed entries
  show NAME                           Show raw config block for NAME (fzf if no NAME)
  connect NAME                        Run 'ssh NAME' after selecting NAME (fzf if no NAME)
  help                                Show this help

Notes:
- Managed blocks are marked so the script only edits entries it created.
- If fzf is installed, operations that require a NAME but none is provided
  will prompt with fzf for interactive selection.
EOF
}

ensure_config_exists() {
    if [ ! -d "$HOME/.ssh" ]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
    fi
    if [ ! -f "$SSH_CONFIG" ]; then
        touch "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
    fi
}

backup_config() {
    ensure_config_exists
    mkdir -p "$BACKUP_DIR"
    timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
    cp -p "$SSH_CONFIG" "$BACKUP_DIR/config.$timestamp"
}

# Return 0 and print list of managed names, one per line
list_managed() {
    ensure_config_exists
    awk -v prefix="$MARK_PREFIX" 'index($0,prefix)==1 {sub(prefix,""); sub("\r","",$0); name=substr($0,1); gsub(/^[ \\t]+|[ \\t]+$/,"",name); print name}' "$SSH_CONFIG" | sed 's/:$//'
}

# Extract block for name
get_block() {
    local name="$1"
    ensure_config_exists
    awk -v start="$MARK_PREFIX${name}" -v end="$MARK_SUFFIX${name}" '
    { if ($0==start) {printing=1; print; next} }
    printing==1 { print; if ($0==end) { exit } }
    ' "$SSH_CONFIG"
}

# Remove block for name
remove_block() {
    local name="$1"
    ensure_config_exists
    if ! grep -qF "$MARK_PREFIX${name}" "$SSH_CONFIG"; then
        echo "No managed entry named '$name' found." >&2
        return 1
    fi
    backup_config
    # Use awk to skip block
    awk -v start="$MARK_PREFIX${name}" -v end="$MARK_SUFFIX${name}" '
    { if ($0==start) {inblock=1; next} }
    inblock==1 { if ($0==end) {inblock=0; next} }
    inblock!=1 { print }
    ' "$SSH_CONFIG" > "$SSH_CONFIG".tmp && mv "$SSH_CONFIG".tmp "$SSH_CONFIG"
    echo "Removed managed entry '$name'."
}

# Add or replace block
add_or_update_block() {
    local name="$1"; shift
    local host hostname user port identity proxyjump
    local local_forwards=()
    local remote_forwards=()

    # parse remaining flags (simple loop)
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --host) hostname="$2"; shift 2;;
            --hostname) hostname="$2"; shift 2;;
            --user) user="$2"; shift 2;;
            --port) port="$2"; shift 2;;
            --identity|--identityfile) identity="$2"; shift 2;;
            --proxyjump|--proxy-jump|--jump) proxyjump="$2"; shift 2;;
            --local-forward) local_forwards+=("$2"); shift 2;;
            --remote-forward) remote_forwards+=("$2"); shift 2;;
            --help) show_help; return 0;;
            *) echo "Unknown option: $1" >&2; return 2;;
        esac
    done

    ensure_config_exists

    # Build the block text
    block="${MARK_PREFIX}${name}\nHost ${name}\n"
    [ -n "${hostname-}" ] && block+="    HostName ${hostname}\n"
    [ -n "${user-}" ] && block+="    User ${user}\n"
    [ -n "${port-}" ] && block+="    Port ${port}\n"
    [ -n "${identity-}" ] && block+="    IdentityFile ${identity}\n"
    if [ -n "${proxyjump-}" ]; then
        block+="    ProxyJump ${proxyjump}\n"
    fi
    for lf in "${local_forwards[@]}"; do
        # Accept formats like LPORT:host:port or "LPORT host port"
        block+="    LocalForward ${lf}\n"
    done
    for rf in "${remote_forwards[@]}"; do
        block+="    RemoteForward ${rf}\n"
    done
    block+="${MARK_SUFFIX}${name}\n"

    # If exists remove old one
    if grep -qF "${MARK_PREFIX}${name}" "$SSH_CONFIG"; then
        backup_config
        # remove old
        awk -v start="$MARK_PREFIX${name}" -v end="$MARK_SUFFIX${name}" '
        { if ($0==start) {inblock=1; next} }
        inblock==1 { if ($0==end) {inblock=0; next} }
        inblock!=1 { print }
        ' "$SSH_CONFIG" > "$SSH_CONFIG".tmp && mv "$SSH_CONFIG".tmp "$SSH_CONFIG"
    else
        backup_config
    fi

    # Append new block
    printf "%b\n" "$block" >> "$SSH_CONFIG"
    echo "Added/Updated managed entry '$name'."
}

# Choose a name by fzf if available
choose_name_fzf() {
    local list
    list=$(list_managed || true)
    if [ -z "$list" ]; then
        echo "No managed entries found." >&2
        return 1
    fi
    if command -v fzf >/dev/null 2>&1; then
        printf "%s" "$list" | fzf --height=40% --border --ansi
    else
        # fallback to simple select
        echo "fzf not installed; printing entries and asking for choice:" >&2
        printf "%s\n" "$list"
        printf "Enter name: " >&2
        read -r choice
        printf "%s" "$choice"
    fi
}

# Show managed list in a pretty way
list_pretty() {
    ensure_config_exists
    awk -v prefix="$MARK_PREFIX" '
    index($0,prefix)==1 { name=substr($0,length(prefix)+1); sub(/:\\r?$/,"",name); printf "%s\n", name }
    ' "$SSH_CONFIG"
}

# Show block content raw
show_block() {
    local name="$1"
    if [ -z "$name" ]; then
        name=$(choose_name_fzf) || return 1
    fi
    get_block "$name" || return 1
}

# Connect using ssh (ssh will use Host alias in config)
connect_host() {
    local name="$1"
    if [ -z "$name" ]; then
        name=$(choose_name_fzf) || return 1
    fi
    if ! grep -qF "${MARK_PREFIX}${name}" "$SSH_CONFIG"; then
        echo "No managed entry named '$name' found." >&2
        return 1
    fi
    echo "Running: ssh $name"
    exec ssh "$name"
}

# Parse top-level command
if [ "$#" -lt 1 ]; then
    show_help
    exit 1
fi

cmd="$1"; shift
case "$cmd" in
    help|-h|--help) show_help; exit 0;;
    list)
        list_pretty
        exit 0
        ;;
    add)
        if [ $# -lt 1 ]; then
            echo "Usage: s.sh add NAME [options]" >&2; exit 2
        fi
        name="$1"; shift
        add_or_update_block "$name" "$@"
        ;;
    update)
        if [ $# -lt 1 ]; then
            echo "Usage: s.sh update NAME [options]" >&2; exit 2
        fi
        name="$1"; shift
        add_or_update_block "$name" "$@"
        ;;
    remove|rm|delete)
        name="${1-}"
        if [ -z "$name" ]; then
            name=$(choose_name_fzf) || exit 1
        fi
        remove_block "$name"
        ;;
    show)
        name="${1-}"
        show_block "$name"
        ;;
    connect|ssh)
        name="${1-}"
        connect_host "$name"
        ;;
    *)
        echo "Unknown command: $cmd" >&2
        show_help
        exit 2
        ;;
esac
