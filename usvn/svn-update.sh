#!/usr/bin/bash

echo_time() {
	echo "#### $(date +%F-%H:%M:%S) $*"
}

main() {
    # set -xe
    script_path="$(dirname "$(readlink -f "$0")")"
    script_name="$(basename "$0")"
    script_log=$script_path/$script_name.log
    lock_myself=/tmp/svn.update.lock
    path_svn_checkout=/root/svn_checkout
    export LANG='en_US.UTF-8'
    # export LC_CTYPE='en_US.UTF-8'
    # export LC_ALL='en_US.UTF-8'
    rsync_conf=$script_path/rsync.deploy.conf
    rsync_exclude=$script_path/rsync.exclude.conf
    rsync_opt="rsync -avz --exclude=.svn --exclude=.git"
    if [ -f "$rsync_exclude" ]; then
        rsync_opt="$rsync_opt --exclude-from=$rsync_exclude"
    fi
    if [ -f "$script_path/rsync.debug" ]; then
        rsync_opt="$rsync_opt -n"
        debug_on=1
    fi
    if [ -f "$script_path/rsync.delete.confirm" ]; then
        rsync_opt="$rsync_opt --delete-after"
    fi

    if [ -f $lock_myself ]; then
        # echo_time "$(date) lock file exists. exit."
        exit 0
    fi
    exec &> >(tee -a "$script_log")
    touch $lock_myself
    trap 'rm -f "$lock_myself"; exit $?' INT TERM EXIT

    ## trap: do some work
    ## post-commit generate /tmp/svn_need_update.*
    for file in /tmp/svn_need_update.*; do
        [ -f "$file" ] || continue

        echo_time "svn need update $file"
        repo_name=${file##*.}
        if [[ ! -d /var/www/usvn/files/svn/${repo_name:-none} ]]; then
            echo_time "Not found repo: ${repo_name:-none}"
            return
        fi
        ## 1, svn checkout repo
        if [ ! -d "$path_svn_checkout/$repo_name/.svn" ]; then
            mkdir -p "$path_svn_checkout/$repo_name"
            /usr/bin/svn checkout "file:///var/www/usvn/files/svn/$repo_name" "$path_svn_checkout/$repo_name"
        fi
        ## 2, svn update repo and rsync to dest
        while read -r dir_svn; do
            echo_time "svn update $path_svn_checkout/$repo_name/$dir_svn"
            /usr/bin/svn update --no-auth-cache -N "$path_svn_checkout/$repo_name/$dir_svn"
            chown -R 1000.1000 "$path_svn_checkout/$repo_name/$dir_svn"
            count=0
            ## get user@host_ip:/path/to/dest from $rsync_conf
            if [ ! -f "$rsync_conf" ]; then
                echo_time "Not found $rsync_conf, skip rsync."
                return
            fi
            while read -r line_rsync_conf; do
                rsync_src="$path_svn_checkout/$repo_name/${dir_svn%/}/"
                user_ip="$(echo "$line_rsync_conf" | awk '{print $2}')"
                rsync_dest="$(echo "$line_rsync_conf" | awk '{print $3}')/$repo_name/${dir_svn%/}/"
                [[ "$debug_on" == 1 ]] && echo_time "$rsync_src $user_ip:$rsync_dest"
                $rsync_opt "$rsync_src" "$user_ip":"$rsync_dest" && count=$((count + 1))
            done < <(grep "^$repo_name" "$rsync_conf")

        done <"$file"
        [ $count -gt 0 ] && rm -f "$file"
    done
    ## trap: end some work

    rm $lock_myself
    trap - INT TERM EXIT
}

main "$@"
