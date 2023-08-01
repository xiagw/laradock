#!/usr/bin/env bash

_log() {
    echo "[$(date +%F_%T)], $*" >>"$me_log"
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
        sleep 59
    done
}

_kill() {
    echo "receive SIGTERM, kill ${pids[*]}"
    for pid in "${pids[@]}"; do
        kill "$pid"
        wait "$pid"
    done
}

_watch_new() {
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
        done
}

main() {
    # set -xe
    export LANG='en_US.UTF-8'
    # export LC_CTYPE='en_US.UTF-8'
    # export LC_ALL='en_US.UTF-8'
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="${me_path}/${me_name}.log"

    path_www=/var/www
    path_usvn=$path_www/usvn
    path_svn_pre=$path_usvn/files/svn
    path_svn_checkout=$path_www/svncheckout
    bin_svn=/usr/bin/svn
    bin_svnlook=/usr/bin/svnlook

    if [[ ! -d $path_svn_pre ]]; then
        mkdir -p $path_svn_pre
    fi
    chown -R 33:33 $path_usvn/{config,files}
    if [[ ! -d $path_usvn/public ]]; then
        rsync -a ${path_usvn}_src/ $path_usvn/
    fi

    ## schedule svn cleanup/update root dirs
    _schedule_svn_update &

    ## 识别中断信号，停止 java 进程
    trap _kill HUP INT PIPE QUIT TERM
    pids=()
    _watch_new
    # svnserve -d -r $path_svn_pre
    ## start apache
    apache2-foreground &
    pids+=("$!")
    wait
}

main "$@"
