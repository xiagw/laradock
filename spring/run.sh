#!/usr/bin/env bash

_start() {
    cj=0
    for jar in "$me_path"/*.jar; do
        [[ -f "$jar" ]] || continue
        cj=$((cj + 1))
        cy=0
        echo "${cj}. found $jar"
        ## !!! 注意 注意 注意  !!!,
        ## 自动探测 yml 配置文件
        ## 按文件名字母顺序自动排序对应 a.jar--a.yml, b.jar--b.yml
        for y in "$me_path"/*.yml; do
            [[ -f "$y" ]] || continue
            cy=$((cy + 1))
            echo "${cy}. found $y"
            [[ "$cj" -eq "$cy" ]] && profile_name="-Dspring.config.location=${y}"
        done
        echo "[INFO] start $jar..."
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

main() {
    me_path="$(dirname "$(readlink -f "$0")")"
    me_name="$(basename "$0")"
    me_log="${me_path}/${me_name}.log"
    date >>"$me_log"
    [ -d "$me_path"/log ] || mkdir "$me_path"/log

    ## 修改内存占用值，
    JAVA_OPTS='java -Xms1024m -Xmx1024m'
    ## 获取中断信号，停止 java 进程
    trap _kill HUP INT QUIT TERM
    ## 启动 java 进程
    _start
    ## 适用于 docker 中启动
    wait
}

main "$@"
