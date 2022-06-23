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
    # cat ~/.ssh/id_ed25519.pub
}

main() {
    ## web app usvn
    if [ ! -d /var/www/usvn/public ]; then
        rsync -a /var/www/usvn_src/ /var/www/usvn/
    fi

    ## start lsyncd
    conf_lsyncd=~/.ssh/lsyncd.conf
    if [ -f $conf_lsyncd ]; then
        lsyncd $conf_lsyncd
    fi

    _generate_ssh_key

    ## svn update /svn_checkout/
    while true; do
        if [ -f ~/.ssh/svn-update.sh ]; then
            bash ~/.ssh/svn-update.sh &
        fi
        sleep 15
    done &

    ## start apache
    apache2-foreground
}

main "$@"
