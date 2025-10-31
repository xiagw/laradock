#!/usr/bin/env bash

set -xe
mode="${1}"
## Determine paths
me_path="$(dirname "$(readlink -f "$0")")"
## Laradock root path, up one level
laradock_path="$(dirname "${me_path}")"
## Laradock data path, up two levels then into laradock-data
laradock_data="$(dirname "$(dirname "${laradock_path}")")/laradock-data"
## get GitLab domain from .env file
domain_git=$(grep '^GITLAB_DOMAIN_NAME_GIT' "${laradock_path}/.env" | cut -d'=' -f2)
# remove git. prefix for base domain
domain_base=${domain_git#git.}

cd "$laradock_path"

case "$mode" in
-s | --ssl)
    echo "Updating GitLab SSL certificates for domain: $domain_git"
    gitlab_ssl_path="${laradock_data}/gitlab/config/ssl"
    cert_path=$HOME/.acme.sh/dest

    [ -d "$gitlab_ssl_path" ] || sudo mkdir -p "$gitlab_ssl_path"
    openssl x509 -enddate -noout -in "$cert_path/${domain_base}".pem
    sudo ls -al "$cert_path/${domain_base}".* "$gitlab_ssl_path/${domain_git}".*
    sudo cp "$cert_path/${domain_base}".key "$gitlab_ssl_path/${domain_git}".key
    sudo cp "$cert_path/${domain_base}".pem "$gitlab_ssl_path/${domain_git}".crt
    echo "SSL certificates copied to GitLab directory, restarting Nginx..."
    docker compose exec gitlab "gitlab-ctl restart nginx"
    ;;
-n | --nginx)
    echo "Updating GitLab Nginx configuration for domain: $domain_base"
    gitlab_nginx_conf="${laradock_data}/gitlab/data/nginx/conf"
    sudo cp -vf "${me_path}/custom.conf" "$gitlab_nginx_conf/"
    sudo sed -i -e "s/example.com/$domain_base/g" "$gitlab_nginx_conf/custom.conf"
    echo "Nginx configuration updated, restarting Nginx..."
    docker compose exec gitlab "gitlab-ctl restart nginx"
    ;;
full)
    echo "Full backup including uploads, builds, artifacts, lfs, terraform_state, registry, repositories, packages."
    docker compose exec gitlab gitlab-backup create
    ;;
*)
    echo "Partial backup only postgresql, skipping uploads, builds, artifacts, lfs, terraform_state, registry, repositories, packages."
    docker compose exec gitlab gitlab-backup create SKIP=uploads,builds,artifacts,lfs,terraform_state,registry,repositories,packages
    ;;
esac
