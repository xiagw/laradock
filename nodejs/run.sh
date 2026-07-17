#!/usr/bin/bash

cleanup() {
    _msg "receive SIGTERM, kill ${pids[*]}"
    for pid in "${pids[@]}"; do
        kill "$pid"
        wait "$pid"
    done
}

main() {
    pids=()
    trap cleanup HUP INT PIPE QUIT TERM

    me_path="$(dirname "$(readlink -f "$0")")"
    cd "$me_path" || exit 1

    echo "start at $(date)"

    npm_install=false
    # check if package.json changed
    pkg=package.json
    pkgmd5="$pkg".md5
    if [ -f "$pkg" ]; then
        echo "found $pkg"
        md5_new=$(md5sum "$pkg" | cut -d' ' -f1)

        if [ -f "$pkgmd5" ]; then
            md5_old=$(cat "$pkgmd5")
            if [ "$md5_new" = "$md5_old" ]; then
                echo "$pkg not changed, npm install not required"
            else
                echo "$pkg changed, npm install required"
                npm_install=true
            fi
        else
            echo "$md5_new" >"$pkgmd5"
        fi

        if [ ! -d node_modules ]; then
            echo "not found directory: node_modules/"
            npm_install=true
        fi

        if [ "${npm_install:-false}" = "true" ]; then
            if command -v cnpm; then
                cnpm install
            else
                npm install
            fi
        fi

        if [ -d ./src ]; then
            echo "found ./src/, npm run start..."
            ## fixed npm run start
            npm run start
            # echo "get start cmd from $pkg"
            # start_cmd=$(awk '/"start".*\.[js|ts]/ {gsub(/"/,""); gsub(/start:/,""); gsub(/^\s+/,""); print $0}' "$pkg")
            # if [ -z "$start_cmd" ]; then
            #     echo "not found start cmd from "$pkg""
            #     tail -f "$pkg" &
            # else
            #     echo "get start cmd: $start_cmd"
            #     eval $start_cmd &
            # fi
        else
            echo "not found ./src/"
            tail -f "$pkg" &
        fi
    else
        echo "not found $pkg"
        tail -f /etc/os-release &
    fi

    pids+=("$!")

    wait
}

main "$@"
