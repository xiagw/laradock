#!/bin/bash

main() {
    ## web app usvn
    if [[ ! -d /var/www/usvn/public ]]; then
        rsync -a /var/www/usvn_src/ /var/www/usvn/
    fi

    ## svn update /svn_checkout/
    if [ -f ~/tool/svn-update.sh ]; then
        bash ~/tool/svn-update.sh &
    elif [ -f ~/svn-update.sh ]; then
        bash ~/svn-update.sh &
    fi

    ## start apache
    exec apache2-foreground
}

main "$@"
