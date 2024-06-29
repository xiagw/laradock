#!/usr/bin/env bash


set -xe
me_path="$(dirname "$(readlink -f "$0")")"
cd "${me_path}/.."
docker compose exec gitlab gitlab-backup create SKIP=uploads,builds,artifacts,lfs,terraform_state,registry,repositories,packages

