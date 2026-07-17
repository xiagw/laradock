#!/usr/bin/env bash
set -e
shopt -s nullglob

WORKDIR="${SPRING_WORKDIR:-/app}"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

pids=()
shutdown_requested=0

shutdown() {
  shutdown_requested=1
  echo "[spring] shutting down..."
  for pid in "${pids[@]}"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done

  # Give jar processes a short grace period before forcing them
  deadline=$((SECONDS + 10))
  while [ ${#pids[@]} -gt 0 ] && [ $SECONDS -lt $deadline ]; do
    alive=()
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        alive+=("$pid")
      fi
    done
    if [ ${#alive[@]} -eq 0 ]; then
      break
    fi
    sleep 1
  done

  for pid in "${pids[@]}"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done
  wait
  exit 0
}

trap shutdown TERM INT

if [ -n "$SPRING_JAR" ]; then
  exec java $JAVA_OPTS -jar "$SPRING_JAR"
fi

if [ "$SPRING_AUTO_DETECT" = "true" ] || [ -z "$SPRING_AUTO_DETECT" ]; then
  jars=(*.jar)

  for jar in "${jars[@]}"; do
    echo "[spring] starting jar: $jar"
    java $JAVA_OPTS -jar "$jar" &
    pids+=("$!")
  done

  wait_status=0
  for pid in "${pids[@]}"; do
    if wait "$pid"; then
      continue
    else
      status=$?
      wait_status=$status
      echo "[spring] jar process $pid exited with status $status"
      if [ "$shutdown_requested" -eq 0 ]; then
        echo "[spring] stopping remaining jars because one process exited"
        shutdown
      fi
    fi
  done
  exit "$wait_status"

fi

# Fall back to shell-friendly keepalive when no jar is found
exec tail -f /dev/null
