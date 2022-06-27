#!/usr/bin/bash

main() {
    # set -xe
    script_path="$(dirname "$(readlink -f "$0")")"
    script_name="$(basename "$0")"
    script_log=$script_path/$script_name.log
    lock_myself=/tmp/svn.update.lock
    path_svn_checkout=/root/svn_checkout
    exec &> >(tee -a "$script_log")
    export LANG='en_US.UTF-8'
    # export LC_CTYPE='en_US.UTF-8'
    # export LC_ALL='en_US.UTF-8'
    rsync_conf=$script_path/rsync.deploy.conf
    rsync_exclude=$script_path/rsync.exclude.conf
    if [ -f "$script_path/rsync.debug" ]; then
        rsync_opt="rsync -avnz --exclude-from=$rsync_exclude"
    elif [ -f "$script_path/rsync.delete.confirm" ]; then
        rsync_opt="rsync -avz --delete-after --exclude-from=$rsync_exclude"
    else
        rsync_opt="rsync -avz --exclude-from=$rsync_exclude"
    fi
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

        echo -e "\n######## $(date +%F-%T) svn need update $file"
        repo_name=${file##*.}
        ## 1, svn checkout repo
        if [ ! -d "$path_svn_checkout/$repo_name/.svn" ]; then
            mkdir -p "$path_svn_checkout/$repo_name"
            /usr/bin/svn checkout "file:///var/www/usvn/file/svn/$repo_name" "$path_svn_checkout/$repo_name"
        fi
        ## 2, svn update repo and rsync to dest
        while read -r line; do
            echo "######## $(date +%F-%T) svn update $path_svn_checkout/$repo_name/$line"
            /usr/bin/svn update --no-auth-cache -N "$path_svn_checkout/$repo_name/$line"
            chown -R 1000.1000 "$path_svn_checkout/$repo_name/$line"
            c=0
            ## get user@host_ip:/path/to/dest from $rsync_conf
            if [ ! -f "$rsync_conf" ]; then
                echo "Not found $rsync_conf, skip rsync."
                return
            fi
            while read -r rline; do
                rsync_src="$path_svn_checkout/$repo_name/${line%/}/"
                user_ip="$(echo "$rline" | awk '{print $2}')"
                rsync_dest="$(echo "$rline" | awk '{print $3}')/$repo_name/${line%/}/"
                $rsync_opt "$rsync_src" "$user_ip":"$rsync_dest" && c=$((c + 1))
            done < <(grep "^$repo_name" "$rsync_conf")
            [ $c -gt 0 ] && safe_del=true || safe_del=false
        done <"$file"
        [[ "$safe_del" == 'true' ]] && rm -f "$file"
    done
    ## trap: end some work

    rm $lock_myself
    trap - INT TERM EXIT
}

main "$@"
