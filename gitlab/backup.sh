#!/usr/bin/env bash

set -xe
me_path="$(dirname "$(readlink -f "$0")")"
laradock_path="$(dirname "${me_path}")"
laradock_data="$(dirname "${laradock_path}")/laradock-data"
domain_git=$(grep '^GITLAB_DOMAIN_NAME_GIT' "${laradock_path}/.env" | cut -d'=' -f2)
domain_base=${domain_git#git.}

cd "$laradock_path"

case "$1" in
-s | --ssl)
    gitlab_ssl_path="${laradock_data}/gitlab/config/ssl"
    cert_path=$HOME/.acme.sh/dest

    [ -d "$gitlab_ssl_path" ] || sudo mkdir -p "$gitlab_ssl_path"
    openssl x509 -enddate -noout -in "$cert_path/${domain_base}".pem
    sudo ls -al "$cert_path/${domain_base}".* "$gitlab_ssl_path/${domain_git}".*
    sudo cp "$cert_path/${domain_base}".key "$gitlab_ssl_path/${domain_git}".key
    sudo cp "$cert_path/${domain_base}".pem "$gitlab_ssl_path/${domain_git}".crt
    docker compose exec gitlab "gitlab-ctl restart nginx"
    ;;
-n | --nginx)
    gitlab_nginx_conf="${laradock_data}/gitlab/data/nginx/conf"
    sudo cp -vf "${me_path}/nginx.ext.conf" "$gitlab_nginx_conf/nginx.ext.conf"
    sudo sed -i -e "s/example.com/$domain_base/g" "$gitlab_nginx_conf/nginx.ext.conf"
    docker compose exec gitlab "gitlab-ctl restart nginx"
    ;;
full)
    docker compose exec gitlab gitlab-backup create
    ;;
*)
    docker compose exec gitlab gitlab-backup create SKIP=uploads,builds,artifacts,lfs,terraform_state,registry,repositories,packages
    ;;
esac
