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

if [ -d ./src ]; then
    echo "found ./src"
    start_cmd=$(awk '/"start".*\.js/ {gsub(/"/,""); gsub(/start:/,""); gsub(/^\s+/,""); print $0}' nodejs/package.json)
    eval $start_cmd &
else
    echo "not found ./src"
    tail -f package.json &
fi

pids+=("$!")

wait
