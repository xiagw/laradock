#!/usr/bin/env bash

main() {
    me_name="$(basename "$0")"
    me_path="$(dirname "$(readlink -f "$0")")"
    me_log="${me_path}/${me_name}.log"

    build_opt="docker build"

    while [[ "${#}" -ge 0 ]]; do
        case $1 in
        china | cn)
            build_opt="$build_opt --build-arg CHANGE_SOURCE=true"
            ;;
        8.0 | 8.1)
            os_ver=22.04
            php_ver=$1
            break
            ;;
        5.6 | 7.1 | 7.2 | 7.4)
            os_ver=20.04
            php_ver=$1
            break
            ;;
        *)
            os_ver=20.04
            php_ver=7.1
            break
            ;;
        esac
        shift
    done

    build_opt="$build_opt --build-arg OS_VER=$os_ver --build-arg LARADOCK_PHP_VERSION=$php_ver"
    image_tag_base=deploy/php:${php_ver}-base
    image_tag=deploy/php:${php_ver}
    file_url=https://gitee.com/xiagw/laradock/raw/in-china/php-fpm
    file_base=Dockerfile.php-base

    cd "$me_path" || exit 1

    ## php base image ready?
    echo "Check php base image [$image_tag_base] ..."
    if ! docker images | grep -q "$image_tag_base"; then
        if [[ ! -f $file_base ]]; then
            curl -fsSLO $file_url/$file_base
        fi
        $build_opt -t "$image_tag_base" -f $file_base . || return 1
    fi

    ## build php image
    echo "Build php image [$image_tag] ..."
    echo "FROM $image_tag_base" >Dockerfile
    [[ -d root ]] || mkdir root
    $build_opt -t "$image_tag" -f Dockerfile .
}

main "$@"
