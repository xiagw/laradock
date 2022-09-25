#!/usr/bin/env bash

# set -xe
export LANG='en_US.UTF-8'
# export LC_CTYPE='en_US.UTF-8'
# export LC_ALL='en_US.UTF-8'
script_path="$(dirname "$(readlink -f "$0")")"
script_name="$(basename "$0")"
script_log="${script_path}/${script_name}.log"
lock_myself=/tmp/.svn.update.lock

_log() {
    echo "[$(date +%F_%T)], $*" >>"$script_log"
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
            _log "svn cleanup/update root dir" | tee -a "$script_log"
            for d in "$path_svn_checkout"/*/; do
                [ -d "$d"/.svn ] || continue
                svn cleanup "$d"
                svn update "$d"
            done
        fi
        sleep 50
    done
}

_cleanup() {
    rm -f $lock_myself
}

main() {
    path_svn_pre=/var/www/usvn/files/svn
    path_svn_checkout=${script_path}/svn_checkout
    ## allow only one instance
    if [ -f "$lock_myself" ]; then exit 0; fi
    ## schedule svn cleanup/update root dirs
    _schedule_svn_update &
    ## ssh key
    _generate_ssh_key
    # exec &> >(tee -a "$script_log")
    touch "$lock_myself"
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
                # chown -R 1000.1000 "$path_svn_checkout/$repo_name/${dir_changed}"
            done
        done
    ## trap: end some work

    _cleanup
    trap - INT TERM EXIT
}

main "$@"
