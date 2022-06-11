#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091

main() {
    for d in /var/www/*; do
        if [ ! -d "$d" ]; then
            continue
        fi
        cd "${d}" || exit 1
        if [[ -f task.sh ]]; then
            chmod +x task.sh
            bash ./task.sh
        fi
    done
}

main "$@"
