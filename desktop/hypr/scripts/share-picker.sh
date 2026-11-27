#!/usr/bin/env bash

flag="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/share-picker-next"

window_handle() {
    local want=$(( $1 )) entry handle rest addr
    local list="${XDPH_WINDOW_SHARING_LIST//\[HA>\]/$'\n'}"
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        handle="${entry%%\[HC>\]*}"
        addr="${entry##*\[HE>\]}"
        [[ "$addr" =~ ^(0x)?[0-9a-fA-F]+$ ]] || continue
        [[ "$addr" == 0x* ]] || [[ "$addr" =~ ^[0-9]+$ ]] || addr="0x$addr"
        if (( addr == want )); then
            echo "$handle"
            return 0
        fi
    done <<< "$list"
    return 1
}

if [[ -f "$flag" ]] && (( $(date +%s) - $(stat -c %Y "$flag") <= 30 )); then
    target=$(<"$flag")
    rm -f "$flag"
    case "$target" in
        window:*)
            if handle=$(window_handle "${target#window:}"); then
                echo "[SELECTION]/window:$handle"
                exit 0
            fi
            mon=$(hyprctl monitors -j | jq -r 'sort_by(.x) | .[0].name')
            [[ -n "$mon" ]] && { echo "[SELECTION]/screen:$mon"; exit 0; }
            ;;
        screen:*) echo "[SELECTION]/$target"; exit 0 ;;
        ?*) echo "[SELECTION]/screen:$target"; exit 0 ;;
    esac
fi
rm -f "$flag"

exec hyprland-share-picker "$@"
