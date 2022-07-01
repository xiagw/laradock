#!/usr/bin/env bash

echo_time() {
    echo "#### $(date +%F_%T) $*"
}

_generate_ssh_key() {
    ## generate ssh key
    if [ ! -f ~/.ssh/id_ed25519 ]; then
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        ssh-keygen -t ed25519 -C "root@usvn.docker" -N '' -f ~/.ssh/id_ed25519
        ## set StrictHostKeyChecking no
        (
            echo 'Host *'
            echo 'IdentityFile ~/.ssh/id_ed25519'
            echo 'StrictHostKeyChecking no'
            echo 'Compression yes'
        ) >~/.ssh/config
        chmod 600 ~/.ssh/config
    fi
    # cat ~/.ssh/id_ed25519.pub
}

_start_lsyncd() {
    ## start lsyncd
    conf_lsyncd=~/.ssh/lsyncd.conf
    if [ -f $conf_lsyncd ]; then
        lsyncd $conf_lsyncd
    fi
}

_schedule_svn_update() {
    while true; do
        ## UTC time
        if [[ "$(date +%H)" == 20 ]]; then
            for d in "$path_svn_checkout"/*/; do
                svn cleanup "$d"
                svn update "$d"/
            done
        fi
        sleep 600
    done
}

main() {
    # set -xe
    export LANG='en_US.UTF-8'
    # export LC_CTYPE='en_US.UTF-8'
    # export LC_ALL='en_US.UTF-8'
    script_path="$(dirname "$(readlink -f "$0")")"
    script_name="$(basename "$0")"
    script_log=${script_path}/${script_name}.log
    path_svn_pre=/var/www/usvn/files/svn
    path_svn_checkout=/root/svn_checkout
    rsync_conf=$script_path/rsync.deploy.conf

    lock_myself=/tmp/svn.update.lock
    if [ -f $lock_myself ]; then exit 0; fi
    ## schedule svn update root dirs
    _schedule_svn_update &
    ## ssh key
    _generate_ssh_key
    ## debug log
    exec &> >(tee -a "$script_log")
    touch $lock_myself
    trap 'rm -f "$lock_myself"; exit $?' INT TERM EXIT

    ## trap: do some work
    inotifywait -m -r -e create --excludei 'db/transactions/' ${path_svn_pre}/ |
        grep -vE '/db/ CREATE|/db/txn' --line-buffered |
        while read -r path; do
            ## get $repo_name
            repo_name=${path#"${path_svn_pre}"/}
            repo_name=${repo_name%%/*}
            if [[ ! -d "$path_svn_pre/${repo_name:-none}" ]]; then
                echo_time "not found repo: ${repo_name:-none}"
                continue
            fi
            ## svnlook dirs-change
            sleep 2
            for dir_changed in $(/usr/bin/svnlook dirs-changed "$path_svn_pre/${repo_name}"); do
                echo_time "svnlook dirs-changed: $dir_changed"
                ## not found svn repo in /root/svn_checkout, then svn checkout
                if [ ! -d "$path_svn_checkout/$repo_name/.svn" ]; then
                    /usr/bin/svn checkout "file://$path_svn_pre/$repo_name" "$path_svn_checkout/$repo_name"
                fi
                ## svn update
                /usr/bin/svn update "$path_svn_checkout/$repo_name/${dir_changed}"
                chown -R 1000.1000 "$path_svn_checkout/$repo_name/${dir_changed}"
                if [ ! -f "$rsync_conf" ]; then
                    echo_time "not found $rsync_conf, skip rsync."
                    continue
                fi
                ## setup rsync options
                rsync_opt="rsync -az --exclude=.svn --exclude=.git"
                rsync_exclude=$script_path/rsync.exclude.conf
                [ -f "$rsync_exclude" ] && rsync_opt="$rsync_opt --exclude-from=$rsync_exclude"
                [ -f "$script_path/rsync.debug" ] && rsync_opt="$rsync_opt -v"
                [ -f "$script_path/rsync.dryrun" ] && rsync_opt="$rsync_opt -n"
                [ -f "$script_path/rsync.delete.confirm" ] && rsync_opt="$rsync_opt --delete-after"
                ## get user@host_ip:/path/to/dest from $rsync_conf
                while read -r line_rsync_conf; do
                    rsync_src="$path_svn_checkout/$repo_name/${dir_changed%/}/"
                    rsync_user_ip="$(echo "$line_rsync_conf" | awk '{print $2}')"
                    rsync_dest="$(echo "$line_rsync_conf" | awk '{print $3}')/$repo_name/${dir_changed%/}/"
                    echo_time "$rsync_src $rsync_user_ip:$rsync_dest"
                    ssh -n "$rsync_user_ip" "[ -d $rsync_dest ] || mkdir -p $rsync_dest"
                    $rsync_opt "$rsync_src" "$rsync_user_ip":"$rsync_dest"
                done < <(grep "^$repo_name" "$rsync_conf")
            done
        done
    ## trap: end some work

    rm $lock_myself
    trap - INT TERM EXIT
}

main "$@"
