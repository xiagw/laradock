#!/usr/bin/bash

_svn_update() {
    export LANG='en_US.UTF-8'
    export LC_CTYPE='en_US.UTF-8'
    export LC_ALL='en_US.UTF-8'
    svn_update_log=~/.ssh/svn-update.sh.log
    svn_auth=~/.ssh/svn-auth.txt

    [ -f $svn_auth ] && source $svn_auth
    ## post-commit generate /tmp/svn_need_update.*
    for file in /tmp/svn_need_update.*; do
        [ -f "$file" ] || continue
        while read -r line; do
            /usr/bin/svn update \
                --username "${svn_user:-root}" \
                --password "${svn_pass:?empty var}" \
                --no-auth-cache -N "$line"
            chown -R 1000.1000 "$line" && safe_del=true || safe_del=false
        done <"$file"
        echo "svn update $file done" >>$svn_update_log
        [[ "$safe_del" == 'true' ]] && rm -f "$file"
    done
}

main() {
    # path_script="$(dirname "$(readlink -f "$0")")"
    _svn_update
}

main "$@"
