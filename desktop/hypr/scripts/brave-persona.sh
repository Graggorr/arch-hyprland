#!/usr/bin/env bash
set -u
ws="$1"
profile="$2"

clients() { hyprctl clients -j | jq -r '.[] | select(.class == "brave-browser") | .address'; }

declare -A seen
while IFS= read -r a; do [ -n "$a" ] && seen[$a]=1; done < <(clients)

hyprctl dispatch "hl.dsp.exec_cmd([[brave --profile-directory=\"$profile\"]])"

for _ in $(seq 1 60); do
    sleep 0.2
    while IFS= read -r a; do
        [ -z "$a" ] && continue
        if [ -z "${seen[$a]:-}" ]; then
            hyprctl dispatch "hl.dsp.window.move({ workspace = $ws, follow = false, window = \"address:$a\" })"
            seen[$a]=1
        fi
    done < <(clients)
done
