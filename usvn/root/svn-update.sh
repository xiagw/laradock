#!/usr/bin/env bash

# set -xe
export LANG='en_US.UTF-8'
# export LC_CTYPE='en_US.UTF-8'
# export LC_ALL='en_US.UTF-8'
me_path="$(dirname "$(readlink -f "$0")")"
me_name="$(basename "$0")"
me_log="${me_path}/${me_name}.log"
me_lock=/tmp/.svn.update.lock

_log() {
    echo "[$(date +%F_%T)], $*" >>"$me_log"
}

_generate_ssh_key() {
    ## generate ssh key
    [ -f ~/.ssh/id_ed25519 ] && return
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keygen -t ed25519 -C "root@usvn.docker" -N '' -f ~/.ssh/id_ed25519
    (
        echo 'Host *'
        echo 'IdentityFile ~/.ssh/id_ed25519'
        echo 'StrictHostKeyChecking no'
        echo 'GSSAPIAuthentication no'
        echo 'Compression yes'
    ) >~/.ssh/config
    chmod 600 ~/.ssh/config
    # cat ~/.ssh/id_ed25519.pub
}

_schedule_svn_update() {
    while true; do
        ## UTC time
        if [[ "$(date +%H%M)" == 2005 ]]; then
            _log "svn cleanup/update root dir" | tee -a "$me_log"
            for d in "$path_svn_checkout"/*/; do
                [ -d "${d%/}"/.svn ] || continue
                svn cleanup "$d"
                svn update "$d"
            done
        fi
        sleep 50
    done
}

_cleanup() {
    rm -f $me_lock
}

_chown_chmod() {
    args="$1"
    ## ThinkPHP, crate folder runtime / 创建文件夹 runtime
    if [[ "$args" =~ (application) ]]; then
        path_app="${args%/application/*}"
        if [[ -f "$path_app"/.env && -d "$path_app"/vendor && ! -d "$path_app"/runtime ]]; then
            mkdir "$path_app"/runtime
            chown 33:33 "$path_app"/runtime
            chmod 755 "$path_app"/runtime
        fi
    fi
    ## chmod
    if [[ -d "$args" ]]; then
        chmod 755 "$args"
    elif [[ -f "$args" ]]; then
        chmod 644 "$args"
    fi
    ## chown
    if [[ "$args" =~ (runtime) ]]; then
        chown 33:33 "${args%/runtime/*}"/runtime
    elif [[ "$args" =~ (Runtime) ]]; then
        chown 33:33 "${args%/Runtime/*}"/Runtime
    else
        chown 0:0 "$args"
    fi
}

main() {
    path_svn_pre=/var/www/usvn/files/svn
    path_svn_checkout=${me_path}/svn_checkout
    ## allow only one instance
    if [ -f "$me_lock" ]; then
        _log "$me_lock exist, exit."
        return 1
    fi
    ## schedule svn cleanup/update root dirs
    _schedule_svn_update &
    ## ssh key
    _generate_ssh_key
    # exec &> >(tee -a "$me_log")
    touch "$me_lock"
    trap _cleanup INT TERM EXIT HUP
    ## trap: do some work
    inotifywait -mqr -e create --exclude '/db/transactions/|/db/txn-protorevs/' ${path_svn_pre}/ |
        while read -r path action file; do
            echo "${path}${action}${file}" | grep -P '/db/revprops/\d+/CREATE\d+' || continue
            ## get $repo_name
            repo_name=${path#"${path_svn_pre}"/}
            repo_name=${repo_name%%/*}
            if [[ ! -d "$path_svn_pre/${repo_name:-none}" ]]; then
                _log "not found repo: ${repo_name:-none}"
                continue
            fi
            ## svnlook dirs-change
            sleep 2 ## because inotifywait is too fast, need to wait svn write to disk
            for dir_changed in $(/usr/bin/svnlook dirs-changed -r "${file}" "$path_svn_pre/${repo_name}"); do
                _log "svnlook dirs-changed: $dir_changed"
                ## not found svn repo in $path_svn_checkout, then svn checkout
                if [ ! -d "$path_svn_checkout/$repo_name/.svn" ]; then
                    /usr/bin/svn checkout "file://$path_svn_pre/$repo_name" "$path_svn_checkout/$repo_name"
                fi
                ## svn update
                /usr/bin/svn update "$path_svn_checkout/$repo_name/${dir_changed}"
                _chown_chmod "$path_svn_checkout/$repo_name/${dir_changed}"
            done
        done
    ## trap: end some work

    _cleanup
    trap - INT TERM EXIT
}

main "$@"
