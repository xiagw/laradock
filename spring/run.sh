#!/usr/bin/env bash

me_path="$(dirname "$(readlink -f "$0")")"
me_name="$(basename "$0")"
me_log="${me_path}/${me_name}.log"
[ -d "$me_path"/log ] || mkdir "$me_path"/log
date >>"$me_log"

## 修改内存占用值，
if [ -z "$JAVA_OPTS" ]; then
    JAVA_OPTS='java -Xms1024m -Xmx1024m'
fi
## 设置启动调用参数或配置文件
profile_name=
_start() {
    ## start *.jar / 启动所有 jar 包
    cj=0
    for jar in "$me_path"/*.jar; do
        [[ -f "$jar" ]] || continue
        cj=$((cj + 1))
        cy=0
        echo "${cj}. found $jar"
        ## 自动探测 yml 配置文件，覆盖上面的 profile.*
        ## !!!!注意!!!!, 按文件名自动排序对应 a.jar--a.yml, b.jar--b.yml
        for y in "$me_path"/*.yml; do
            [[ -f "$y" ]] || continue
            cy=$((cy + 1))
            [[ "$cj" -eq "$cy" ]] && profile_name="-Dspring.config.location=${y}"
        done
        echo "[INFO] start $jar ..."
        $JAVA_OPTS $profile_name -jar "$jar" &
        pids="$pids $!"
    done
    ## allow debug / 方便开发者调试，可以直接kill java, 不会停止容器
    tail -f "$me_log" "$me_path"/log/*.log &
    pids="$pids $!"
}

_kill() {
    echo "[INFO] Receive SIGTERM"
    for pid in $pids; do
        kill "$pid"
        wait "$pid"
    done
}

trap _kill HUP INT QUIT TERM

_start
## 适用于 docker 中启动
wait
