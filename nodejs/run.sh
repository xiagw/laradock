#!/usr/bin/env bash

if [ -d ./src ]; then
    echo "found ./src"
    start_cmd=$(awk '/"start".*\.js/ {gsub(/"/,""); gsub(/start:/,""); gsub(/^\s+/,""); print $0}' nodejs/package.json)
    eval $start_cmd
else
    echo "not found ./src"
    tail -f package.json
fi
