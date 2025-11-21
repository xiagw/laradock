#!/usr/bin/env bash

set -e
mode="${1:---partial}"
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

cd "$laradock_path" || exit 1

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
-u | --upgrade)
    echo "Upgrading GitLab to the latest version..."
    echo "Pulling the latest GitLab image..."
    docker pull --platform linux/amd64 gitlab/gitlab-ce:latest
    docker tag gitlab/gitlab-ce:latest laradock-gitlab
    echo "Stopping GitLab container..."
    docker compose stop gitlab
    docker compose rm -f gitlab
    echo "Backing up existing PostgreSQL data..."
    sudo cp -a "${laradock_data}/gitlab/data/postgresql" "${laradock_data}/gitlab/data/postgresql_$(date +%Y%m%d_%H%M%S)"
    echo "Starting GitLab container with the new image..."
    docker compose up -d gitlab
    ;;
-f | --full)
    echo "Full backup including uploads, builds, artifacts, lfs, terraform_state, registry, repositories, packages."
    docker compose exec gitlab gitlab-backup create
    ;;
-p | --partial)
    echo "Partial backup only postgresql, skipping uploads, builds, artifacts, lfs, terraform_state, registry, repositories, packages."
    docker compose exec gitlab gitlab-backup create SKIP=uploads,builds,artifacts,lfs,terraform_state,registry,repositories,packages
    ;;
*)
    echo "Usage: $0 [-s|--ssl|-n|--nginx|-u|--upgrade|-f|--full|-p|--partial]"
    echo "  -s, --ssl        Update GitLab SSL certificates"
    echo "  -n, --nginx      Update GitLab Nginx configuration"
    echo "  -u, --upgrade    Upgrade GitLab to the latest version"
    echo "  -f, --full       Perform a full backup of GitLab"
    echo "  -p, --partial    Perform a partial backup of GitLab (default)"
    exit 1
    ;;
esac
