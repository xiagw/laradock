#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091

main() {
    for d in /var/www/*; do
        [[ -d "$d" ]] || continue
        cd "${d}" || exit 1
        if [[ -f task.sh ]]; then
            bash ./task.sh
        fi
    done
}

main "$@"
