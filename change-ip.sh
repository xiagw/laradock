#!/usr/bin/env bash

set -x
cd "$(dirname "$0")" || exit 1

docker_host_ip=$(/sbin/ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
sed -i -e "/DOCKER_HOST_IP=/s/=.*/=$docker_host_ip/" .env

case $docker_host_ip in
'192.168.3.22') ## git
    sed -i -e "/GITLAB_DOMAIN_NAME_GIT=/s/=.*/=git.fly.com/" \
        -e "/GITLAB_DOMAIN_NAME=/s/=.*/=https:\/\/git.fly.com/" \
        -e "/GITLAB_CI_SERVER_URL=/s/=.*/=https:\/\/git.fly.com/" \
        -e "/SONARQUBE_HOSTNAME=/s/=.*/=sonar.fly.com/" \
        -e "/NEXUS_DOMAIN=/s/=.*/=nexus.fly.com/" \
        .env
    ;;
'192.168.3.24') ## dev www1
    sed -i \
        -e "/NGINX_HOST_HTTP_PORT=/s/=.*/=82/" \
        -e "/NGINX_HOST_HTTPS_PORT=/s/=.*/=445/" \
        -e "/APISIX_HOST_HTTP_PORT=/s/=.*/=80/" \
        -e "/APISIX_HOST_HTTPS_PORT=/s/=.*/=443/" \
        -e "/DOCKER_HOST_IP_DB=/s/=.*/=192.168.3.24/" \
        .env
    ;;
*)
    echo "Usage: $0"
    ;;
esac
