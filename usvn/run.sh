#!/bin/sh

## generate ssh key
if [ ! -f ~/.ssh/id_ed25519 ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keygen -t ed25519 -C "lsyncd@svn.com" -N '' -f ~/.ssh/id_ed25519
fi
cat ~/.ssh/id_ed25519.pub
## set StrictHostKeyChecking no
cat >~/.ssh/config <<'EOF'
Host *
IdentityFile ~/.ssh/id_ed25519
StrictHostKeyChecking no
Compression yes
EOF
chmod 600 ~/.ssh/config

## start lsyncd
conf_lsyncd=~/.ssh/lsyncd.conf
if [ -f $conf_lsyncd ]; then
    lsyncd $conf_lsyncd
fi

if [ ! -d /var/www/usvn/public ]; then
    rsync -a /var/www/usvn_src/ /var/www/usvn/
fi
## start apache
apache2-foreground
