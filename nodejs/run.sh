#!/usr/bin/bash

_kill() {
    _msg "receive SIGTERM, kill ${pids[*]}"
    for pid in "${pids[@]}"; do
        kill "$pid"
        wait "$pid"
    done
}

trap _kill HUP INT PIPE QUIT TERM

pids=()

if [ -f package.json ]; then
    echo "found package.json"
    md5_new=$(md5sum package.json | cut -d ' ' -f 1)

    if [ -f package.json.md5 ]; then
        md5_old=$(cat package.json.md5)
        if [ "$md5_new" = "$md5_old" ]; then
            echo "package.json not changed, skip npm install"
        else
            echo "package.json changed, npm install"
            npm_install=true
        fi
    else
        echo "$md5_new" >package.json.md5
    fi

    if [ ! -d node_modules ]; then
        echo "not found node_modules"
        npm_install=true
    fi
    if ${npm_install:-false}; then
        if command -v cnpm; then
            cnpm install
        else
            npm install
        fi
    fi

    if [ -d ./src ]; then
        echo "found ./src"
        npm run start
        # start_cmd=$(awk '/"start".*\.[js|ts]/ {gsub(/"/,""); gsub(/start:/,""); gsub(/^\s+/,""); print $0}' package.json)
        # if [ -z "$start_cmd" ]; then
        #     echo "not found start cmd from package.json"
        #     tail -f package.json &
        # else
        #     echo "get start cmd: $start_cmd"
        #     eval $start_cmd &
        # fi
    else
        echo "not found ./src"
        tail -f package.json &
    fi
else
    echo "not found package.json"
    tail -f /etc/os-release &
fi

pids+=("$!")

wait
