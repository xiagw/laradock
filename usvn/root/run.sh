#!/bin/bash

main() {
    ## web app usvn
    if [[ ! -d /var/www/usvn/public ]]; then
        rsync -a /var/www/usvn_src/ /var/www/usvn/
    fi

    ## svn update /root/tool/svn_checkout/
    if [ -f ~/tool/svn-update.sh ]; then
        bash ~/tool/svn-update.sh &
    elif [ -f ~/svn-update.sh ]; then
        bash ~/svn-update.sh &
    fi
    ## lsyncd /root/tool/lsyncd.conf
    if [ -f ~/tool/lsyncd.conf ]; then
        lsyncd ~/tool/lsyncd.conf
    fi

    ## start apache
    exec apache2-foreground
}

main "$@"
