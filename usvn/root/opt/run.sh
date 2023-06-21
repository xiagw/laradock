#!/usr/bin/env bash

_log() {
    echo "[$(date +%F_%T)], $*" >>"$me_log"
}

_cleanup() {
    rm -f $me_lock
}

_generate_ssh_key() {
    ## generate ssh key
    [ -f "$HOME"/.ssh/id_ed25519 ] && return
    mkdir -m 700 "$HOME"/.ssh
    ssh-keygen -t ed25519 -C "root@usvn.docker" -N '' -f "$HOME"/.ssh/id_ed25519
    (
        echo 'Host *'
        echo 'IdentityFile $HOME/.ssh/id_ed25519'
        echo 'StrictHostKeyChecking no'
        echo 'GSSAPIAuthentication no'
        echo 'Compression yes'
    ) >"$HOME"/.ssh/config
    chmod 600 "$HOME"/.ssh/config
    # cat $HOME.ssh/id_ed25519.pub
}

_schedule_svn_update() {
    ## UTC time
    while [[ "$(date +%H%M)" == 2005 ]]; do
        _log "svn cleanup/update root dir" | tee -a "$me_log"
        for d in "$path_svn_checkout"/*/; do
            [ -d "${d%/}"/.svn ] || continue
            svn cleanup "$d"
            svn update "$d"
        done
        sleep 50
    done
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
    # set -xe
    export LANG='en_US.UTF-8'
    # export LC_CTYPE='en_US.UTF-8'
    # export LC_ALL='en_US.UTF-8'
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="${me_path}/${me_name}.log"
    me_lock=/tmp/.svn.update.lock

    path_svn_pre=/var/www/usvn/files/svn
    path_svn_checkout=/var/www/svncheckout
    bin_svn=/usr/bin/svn
    bin_svnlook=/usr/bin/svnlook

    # if [[ ! -d $path_svn_pre ]]; then
    #     mkdir -p $path_svn_pre
    # fi
    chown -R 33:33 /var/www/*
    ## web app usvn
    if [[ ! -d /var/www/usvn/public ]]; then
        rsync -a /var/www/usvn_src/ /var/www/usvn/
    fi
    ## allow only one instance
    # if [ -f "$me_lock" ]; then
    #     _log "$me_lock exist, exit."
    #     return 1
    # fi
    ## schedule svn cleanup/update root dirs
    _schedule_svn_update &
    ## ssh key
    _generate_ssh_key
    ## lsyncd /root/tool/lsyncd.conf
    # if [ -f /etc/lsyncd/lsyncd.conf.lua ]; then
    #     lsyncd /etc/lsyncd/lsyncd.conf.lua &
    # fi
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
            sleep 2 ## because "inotifywait" is too fast, so need to wait until "svn" write to disk
            for dir_changed in $($bin_svnlook dirs-changed -r "${file}" "$path_svn_pre/${repo_name}"); do
                _log "svnlook dirs-changed: $dir_changed"
                ## not found svn repo in $path_svn_checkout, then svn checkout
                if [ ! -d "$path_svn_checkout/$repo_name/.svn" ]; then
                    $bin_svn checkout "file://$path_svn_pre/$repo_name" "$path_svn_checkout/$repo_name"
                fi
                ## svn update
                echo "${dir_changed}" | grep runtime >>"$me_path"/runtime.log
                $bin_svn update "$path_svn_checkout/$repo_name/${dir_changed}"
                _chown_chmod "$path_svn_checkout/$repo_name/${dir_changed}"
            done
        done &
    ## trap: end some work
    trap _cleanup INT TERM EXIT HUP
    ## start apache
    apache2-foreground
}

main "$@"
