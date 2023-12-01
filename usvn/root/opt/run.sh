#!/usr/bin/env bash

_log() {
    echo "[$(date +%F_%T)], $*" >>"$me_log"
}

_kill() {
    echo "receive SIGTERM, kill ${pids[*]}"
    for pid in "${pids[@]}"; do
        kill "$pid"
        wait "$pid"
    done
}

_schedule_svn_update() {
    ## UTC time
    while [[ "$(date +%H%M)" == 2005 || "$(date +%H%M)" == 0405 ]]; do
        _log "svn cleanup/update root dir" | tee -a "$me_log"
        for d in "$svn_checkout_path"/*/; do
            [ -d "${d%/}"/.svn ] || continue
            svn cleanup "$d"
            svn update "$d"
        done
        sleep 59
    done
}

_inotify() {
    while read -r path action rev; do
        echo "${path}${action}${rev}" | grep -P '/db/revprops/\d+/CREATE\d+' || continue
        ## get $repo_name
        repo_name=${path#"${svn_repo_path}"/}
        repo_name=${repo_name%%/*}
        if [[ ! -d "$svn_repo_path/${repo_name:-none}" ]]; then
            _log "not found $svn_repo_path/${repo_name:-none}"
            continue
        fi
        ## because "inotifywait" is too fast, so need to wait until "svn" write to disk
        sleep 2

        ## svnlook dirs-change
        for dir_changed in $($cmd_svnlook dirs-changed -r "${rev}" "$svn_repo_path/${repo_name}"); do
            _log "svnlook dirs-changed: $dir_changed"
            ## checkout svn repo if not exists
            if [ ! -d "$svn_checkout_path/$repo_name/.svn" ]; then
                echo "Not found $svn_checkout_path/$repo_name/.svn, create..."
                $cmd_svn checkout "file://$svn_repo_path/$repo_name" "$svn_checkout_path/$repo_name"
            fi
            ## svn update
            $cmd_svn update "$svn_checkout_path/$repo_name/${dir_changed%/}"
        done
    done < <(inotifywait -mqr -e create --exclude '/db/transactions/|/db/txn-protorevs/' ${svn_repo_path})
}

main() {
    # set -xe
    export LANG='en_US.UTF-8'
    # export LC_CTYPE='en_US.UTF-8'
    # export LC_ALL='en_US.UTF-8'
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="${me_path}/${me_name}.log"

    www_path=/var/www
    usvn_path=$www_path/usvn
    svn_repo_path=$usvn_path/files/svn
    svn_checkout_path=$www_path/svncheckout
    cmd_svn=/usr/bin/svn
    cmd_svnlook=/usr/bin/svnlook

    if [ -f $usvn_path/debug.on ]; then
        set -xe
    fi
    if [[ -d $usvn_path/public ]]; then
        echo "Found $usvn_path/public, skip copy usvn source code."
    else
        echo "Not found $usvn_path/public, copy usvn source code..."
        rsync -a ${usvn_path}_src/ $usvn_path/
    fi
    if [[ -d $svn_repo_path ]]; then
        echo "Found $svn_repo_path"
    else
        echo "Not found $svn_repo_path, create..."
        mkdir -p $svn_repo_path
    fi
    chown -R 33:33 $usvn_path/{config,files}

    pids=()
    _schedule_svn_update &
    pids+=("$!")

    _inotify &
    pids+=("$!")

    # svnserve -d -r $svn_repo_path

    ## start apache
    apache2-foreground &
    pids+=("$!")

    ## 识别中断信号，停止 java 进程
    trap _kill HUP INT PIPE QUIT TERM SIGWINCH

    wait
}

main "$@"
