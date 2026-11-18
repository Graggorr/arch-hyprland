#!/usr/bin/env bash
# systemd health: invisible when everything is fine, red warning with a count
# (system + user failed units) when something breaks. JSON output ({text,tooltip,class}).
sys=$(systemctl --failed --plain --no-legend 2>/dev/null | grep -c .)
usr=$(systemctl --user --failed --plain --no-legend 2>/dev/null | grep -c .)
total=$((sys + usr))

if (( total == 0 )); then
    printf '{"text": "", "class": "ok", "tooltip": false}\n'
else
    units=$( { systemctl --failed --plain --no-legend 2>/dev/null;
               systemctl --user --failed --plain --no-legend 2>/dev/null; } \
             | awk '{printf "%s%s", sep, $1; sep="\\n"}' )
    printf '{"text": "󰀪  %s", "class": "failed", "tooltip": "Failed systemd units:\\n%s"}\n' "$total" "$units"
fi
