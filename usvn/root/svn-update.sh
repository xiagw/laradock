#!/usr/bin/bash

echo_time() {
    echo "#### $(date +%F-%H:%M:%S) $*"
}

_generate_ssh_key() {
    ## generate ssh key
    if [ ! -f ~/.ssh/id_ed25519 ]; then
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        ssh-keygen -t ed25519 -C "root@usvn.docker" -N '' -f ~/.ssh/id_ed25519
        ## set StrictHostKeyChecking no
        cat >~/.ssh/config <<'EOF'
Host *
IdentityFile ~/.ssh/id_ed25519
StrictHostKeyChecking no
Compression yes
EOF
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

main() {
    # set -xe
    export LANG='en_US.UTF-8'
    # export LC_CTYPE='en_US.UTF-8'
    # export LC_ALL='en_US.UTF-8'
    script_path="$(dirname "$(readlink -f "$0")")"
    script_name="$(basename "$0")"
    script_log=${script_path}/${script_name}.log
    path_svn_pre=/var/www/usvn/files/svn

    lock_myself=/tmp/svn.update.lock
    if [ -f $lock_myself ]; then exit 0; fi

    exec &> >(tee -a "$script_log")
    touch $lock_myself
    trap 'rm -f "$lock_myself"; exit $?' INT TERM EXIT

    ## trap: do some work
    ## ssh key
    _generate_ssh_key

    ## scan svn repo name, copy post-commit to $repo_name/hooks/
    svn_post_commit=$script_path/post-commit
    if [ -f "$svn_post_commit" ]; then
        for d in "$path_svn_pre"/*/; do
            [ -d "$d" ] || continue
            cp "$svn_post_commit" "$d"hooks/
            chmod +x "$d"hooks/post-commit
        done
    fi
    ## setup rsync options
    rsync_opt="rsync -avz --exclude=.svn --exclude=.git"
    rsync_exclude=$script_path/rsync.exclude.conf
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
    ## post-commit generate /var/www/svn_commit/svn_need_update.*
    path_svn_checkout=/root/svn_checkout
    rsync_conf=$script_path/rsync.deploy.conf
    inotifywait -m -e create -e modify -e attrib /var/www/svn_commit/ |
        while read -r path action file; do
            echo_time "$path, $action, $file"
            [ -f "/var/www/svn_commit/$file" ] || continue
            repo_name=${file##*.}
            ## 1, svn update repo and rsync to dest
            while read -r dir_svn; do
                echo_time "svn update $path_svn_checkout/$repo_name/${dir_svn}"
                ## not found $repo_name
                if [[ ! -d "$path_svn_pre/${repo_name:-none}" ]]; then
                    echo_time "Not found repo: ${repo_name:-none}"
                    break
                fi
                ## 2, svn checkout repo
                if [ ! -d "$path_svn_checkout/$repo_name/.svn" ]; then
                    mkdir -p "$path_svn_checkout/$repo_name"
                    /usr/bin/svn checkout "file://$path_svn_pre/$repo_name" "$path_svn_checkout/$repo_name"
                fi
                /usr/bin/svn update --no-auth-cache -N "$path_svn_checkout/$repo_name/${dir_svn}"
                chown -R 1000.1000 "$path_svn_checkout/$repo_name/${dir_svn}"
                count=0
                if [ ! -f "$rsync_conf" ]; then
                    echo_time "Not found $rsync_conf, skip rsync."
                    break
                fi
                ## get user@host_ip:/path/to/dest from $rsync_conf
                while read -r line_rsync_conf; do
                    rsync_src="$path_svn_checkout/$repo_name/${dir_svn%/}/"
                    user_ip="$(echo "$line_rsync_conf" | awk '{print $2}')"
                    rsync_dest="$(echo "$line_rsync_conf" | awk '{print $3}')/$repo_name/${dir_svn%/}/"
                    [[ "$debug_on" == 1 ]] && echo_time "$rsync_src $user_ip:$rsync_dest"
                    ssh -n "$user_ip" "[ -d $rsync_dest ] || mkdir -p $rsync_dest"
                    $rsync_opt "$rsync_src" "$user_ip":"$rsync_dest" && count=$((count + 1))
                done < <(grep "^$repo_name" "$rsync_conf")
            done <"/var/www/svn_commit/$file"
            [ $count -gt 0 ] && rm -f "/var/www/svn_commit/$file"
        done
    ## trap: end some work

    rm $lock_myself
    trap - INT TERM EXIT
}

main "$@"
