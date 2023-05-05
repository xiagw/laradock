#!/bin/bash

_cleanup() {
    rm -f /tmp/.svn.update.lock
}

main() {
    ## web app usvn
    if [[ ! -d /var/www/usvn/public ]]; then
        rsync -a /var/www/usvn_src/ /var/www/usvn/
    fi

    ## svn update /root/tool/svn_checkout/
    if [ -f $HOME/tool/svn-update.sh ]; then
        bash $HOME/tool/svn-update.sh &
    elif [ -f $HOME/svn-update.sh ]; then
        bash $HOME/svn-update.sh &
    fi
    ## lsyncd /root/tool/lsyncd.conf
    if [ -f $HOME/tool/lsyncd.conf.lua ]; then
        lsyncd $HOME/tool/lsyncd.conf.lua
    fi

    trap _cleanup INT TERM EXIT HUP

    ## start apache
    exec apache2-foreground
}

main "$@"
