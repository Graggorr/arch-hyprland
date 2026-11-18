#!/usr/bin/env bash

flag="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/share-picker-next"

if [[ -f "$flag" ]] && (( $(date +%s) - $(stat -c %Y "$flag") <= 30 )); then
    output=$(<"$flag")
    rm -f "$flag"
    if [[ -n "$output" ]]; then
        echo "[SELECTION]/screen:$output"
        exit 0
    fi
fi
rm -f "$flag"

exec hyprland-share-picker "$@"
