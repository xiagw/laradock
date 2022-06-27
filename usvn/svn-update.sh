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
    rsync_exclude=$script_path/rsync.exclude.conf
    # rsync_opt="rsync -avz --delete-after --exclude-from=$rsync_exclude"
    rsync_opt="rsync -avz --exclude-from=$rsync_exclude"
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
        repo_name=${file##*.}
        if [ ! -d "$path_svn_checkout/$repo_name" ]; then
            mkdir -p "$path_svn_checkout/$repo_name"
            /usr/bin/svn checkout "file:///var/www/usvn/file/svn/$repo_name" "$path_svn_checkout/$repo_name"
        fi
        echo -e "\n######## $(date +%F-%T) svn need update $file"
        while read -r line; do
            echo "######## $(date +%F-%T) svn update $path_svn_checkout/$repo_name/$line"
            /usr/bin/svn update --no-auth-cache -N "$path_svn_checkout/$repo_name/$line"
            chown -R 1000.1000 "$path_svn_checkout/$repo_name/$line"
            c=0
            for ip in 33 34 43 58; do
                $rsync_opt "$path_svn_checkout/$repo_name/${line%/}/" root@10.0.5.${ip}:"/nas/new.sync/$repo_name/${line%/}/" && c=$((c + 1))
            done
            $rsync_opt "$path_svn_checkout/$repo_name/${line%/}/" root@192.168.43.232:"/nas/new.sync/$repo_name/${line%/}/" && c=$((c + 1))
            [ $c -gt 0 ] && safe_del=true || safe_del=false
        done <"$file"
        [[ "$safe_del" == 'true' ]] && rm -f "$file"
    done
    ## trap: end some work

    rm $lock_myself
    trap - INT TERM EXIT
}

main "$@"
