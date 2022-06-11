#!/usr/bin/env bash

JAVA_HOME="/data/ubuntu/docker/jdk"
export PATH=$JAVA_HOME/bin:$PATH

## Optimize Memory Allocation with tcmalloc
## First install tcmalloc, then add environment variables to the startup script:
# sudo apt install libgoogle-perftools4
export LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libtcmalloc.so.4"
export TCMALLOC_RELEASE_RATE=10

java -Xmx24g -XX:+UseConcMarkSweepGC -jar FullNode.jar -c main_net_config.conf </dev/null &>/dev/null &


## https://developers.tron.network/docs/fullnode
## download jdk
#
## download FullNode.jar

## download config file
# curl -LO https://raw.githubusercontent.com/tronprotocol/tron-deployment/master/main_net_config.conf
# download snapshot
# curl -LO -C - https://fullnode-backup-3.s3-ap-southeast-1.amazonaws.com/FullNode-31714370-4.2.2.1-output-directory.tgz