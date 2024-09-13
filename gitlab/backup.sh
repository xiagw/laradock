#!/usr/bin/env bash

set -xe
me_path="$(dirname "$(readlink -f "$0")")"
laradock_path="${me_path}/.."
source <(grep '^GITLAB_DOMAIN_NAME_GIT' "${laradock_path}/.env")
domain=${GITLAB_DOMAIN_NAME_GIT#git.}
cd "$laradock_path"

case "$1" in
-s | --ssl)
    gitlab_ssl_path="${laradock_path}/../../laradock-data/gitlab/config/ssl"
    cert_path=$HOME/.acme.sh/dest

    [ -d "$gitlab_ssl_path" ] || sudo mkdir -p "$gitlab_ssl_path"
    openssl x509 -enddate -noout -in "$cert_path/${domain}".pem
    ls -al "$cert_path/${domain}".* "$gitlab_ssl_path/${GITLAB_DOMAIN_NAME_GIT}".*
    sudo cp "$cert_path/${domain}".key "$gitlab_ssl_path/${GITLAB_DOMAIN_NAME_GIT}".key
    sudo cp "$cert_path/${domain}".pem "$gitlab_ssl_path/${GITLAB_DOMAIN_NAME_GIT}".crt
    echo "  docker compose exec gitlab bash -c 'gitlab-ctl restart nginx'"
    ;;
-n | --nginx)
    gitlab_nginx_conf="${laradock_path}/../../laradock-data/gitlab/data/nginx/conf"
    sudo cp -vf "${me_path}/nginx.ext.conf" "$gitlab_nginx_conf/nginx.ext.conf"
    sudo sed -i -e "s/example.com/$domain/g" "$gitlab_nginx_conf/nginx.ext.conf"
    ;;
*)
    docker compose exec gitlab gitlab-backup create SKIP=uploads,builds,artifacts,lfs,terraform_state,registry,repositories,packages
    ;;
esac
