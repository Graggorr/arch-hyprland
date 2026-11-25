#!/usr/bin/env bash
official=$(checkupdates 2>/dev/null | grep -c .)
aur=$(paru -Qua 2>/dev/null | grep -c .)
total=$((official + aur))

report="$HOME/.local/state/claude-agents/system-update-report.txt"
lastrun=""
if [[ -r $report ]]; then
    iso=$(sed -n '1s/^# System update run //p' "$report")
    [[ -n $iso ]] && lastrun=$(date -d "$iso" '+%a %H:%M' 2>/dev/null)
fi

running=$(uname -r)
pkg=linux
[[ $running == *-lts ]] && pkg=linux-lts
installed=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}' | sed 's/\.arch/-arch/')
[[ $pkg == linux-lts ]] && installed="$installed-lts"
reboot=false
[[ -n $installed && $installed != "$running" ]] && reboot=true

if (( total == 0 )); then
    printf '{"text": "", "class": "ok", "tooltip": false, "lastrun": "%s", "reboot": %s}\n' "$lastrun" "$reboot"
else
    printf '{"text": "󰚰  %s", "class": "pending", "tooltip": "%s official + %s AUR updates pending", "lastrun": "%s", "reboot": %s}\n' \
        "$total" "$official" "$aur" "$lastrun" "$reboot"
fi
