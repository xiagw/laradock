#!/bin/bash
_generate_ssh_key() {
    ## generate ssh key
    if [ ! -f ~/.ssh/id_ed25519 ]; then
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        ssh-keygen -t ed25519 -C "lsyncd@svn.com" -N '' -f ~/.ssh/id_ed25519
        ## set StrictHostKeyChecking no
        cat >~/.ssh/config <<'EOF'
Host *
IdentityFile ~/.ssh/id_ed25519
StrictHostKeyChecking no
Compression yes
EOF
        chmod 600 ~/.ssh/config
    fi
    cat ~/.ssh/id_ed25519.pub
}

_start_lsyncd() {
    ## start lsyncd
    conf_lsyncd=~/.ssh/lsyncd.conf
    if [ -f $conf_lsyncd ]; then
        lsyncd $conf_lsyncd
    fi
}

_svn_notify() {
    export LANG='en_US.UTF-8'
    export LC_CTYPE='en_US.UTF-8'
    export LC_ALL='en_US.UTF-8'
    svn_need_update=/tmp/svn_need_update
    [ -f /root/.ssh/svn_auth ] && source /root/.ssh/svn_auth
    if [ -f $svn_need_update ]; then
        while read -r line; do
            /usr/bin/svn update \
                --username "${svn_user:-root}" \
                --password "${svn_pass:?empty var}" \
                --no-auth-cache -N "$line"
            chown -R 1000.1000 "$line"
        done <$svn_need_update ## post-commit
        rm -f $svn_need_update
    fi
}

main() {
    ## web app usvn
    if [ ! -d /var/www/usvn/public ]; then
        rsync -a /var/www/usvn_src/ /var/www/usvn/
    fi

    _generate_ssh_key

    _start_lsyncd

    while true; do
        _svn_notify >/dev/null 2>&1 &
        sleep 10
    done &

    ## start apache
    apache2-foreground
}

main "$@"
