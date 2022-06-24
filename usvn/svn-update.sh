#!/usr/bin/bash

main() {
    # set -xe
    path_script="$(dirname "$(readlink -f "$0")")"
    name_script="$(basename "$0")"
    svn_update_log=$path_script/$name_script.log
    lock_myself=/tmp/svn_update_lock
    svn_checkout=/root/svn_checkout
    exec 1>>"$svn_update_log" 2>&1
    export LANG='en_US.UTF-8'
    # export LC_CTYPE='en_US.UTF-8'
    # export LC_ALL='en_US.UTF-8'
    rsync_exclude=$path_script/rsync.exclude.conf
    rsync_opt="rsync -anz --exclude-from=$rsync_exclude"
    cat >"$rsync_exclude" <<'EOF'
.git
.svn
.bak
.gitignore
.gitattributes
.idea
EOF
    if [ -f $lock_myself ]; then
        # echo "$(date) lock file exists. exit."
        exit 0
    fi
    touch $lock_myself
    trap 'rm -f "$lock_myself"; exit $?' INT TERM EXIT
    ## trap: do some work
    ## post-commit generate /tmp/svn_need_update.*
    for file in /tmp/svn_need_update.*; do
        [ -f "$file" ] || continue
        repo_name=${file#*svn_need_update.}
        repo_name=${repo_name%.*}
        while read -r line; do
            echo "svn update $svn_checkout/$repo_name/$line"
            /usr/bin/svn update --no-auth-cache -N "$svn_checkout/$repo_name/$line"
            chown -R 1000.1000 "$svn_checkout/$repo_name/$line"
            c=0
            # rsync -az "${line%/}/" root@10.0.5.33:/nas/new.sync/ && c=$((c+1))
            # rsync -az "${line%/}/" root@10.0.5.34:/nas/new.sync/ && c=$((c+1))
            # rsync -az "${line%/}/" root@10.0.5.43:/nas/new.sync/ && c=$((c+1))
            # rsync -az "${line%/}/" root@10.0.5.58:/nas/new.sync/ && c=$((c+1))
            rsync_src="$svn_checkout/$repo_name/${line%/}/"
            rsync_dest="root@192.168.43.232:/nas/new.sync/$repo_name/${line%/}/"
            $rsync_opt "$rsync_src" "${rsync_dest}" && c=$((c + 1))
            if [ $c -gt 0 ]; then
                safe_del=true
            else
                safe_del=false
            fi
        done <"$file"

        [[ "$safe_del" == 'true' ]] && rm -f "$file"
    done
    rm $lock_myself
    trap - INT TERM EXIT
}

main "$@"
