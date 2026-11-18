#!/usr/bin/env bash
# Pending updates: official repos (checkupdates) + AUR (paru -Qua).
# Invisible when fully up to date. JSON output ({text,tooltip,class}).
official=$(checkupdates 2>/dev/null | grep -c .)
aur=$(paru -Qua 2>/dev/null | grep -c .)
total=$((official + aur))

if (( total == 0 )); then
    printf '{"text": "", "class": "ok", "tooltip": false}\n'
else
    printf '{"text": "󰚰  %s", "class": "pending", "tooltip": "%s official + %s AUR updates pending"}\n' \
        "$total" "$official" "$aur"
fi
