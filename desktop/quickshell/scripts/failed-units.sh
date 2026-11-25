#!/usr/bin/env bash
sys=$(systemctl --failed --plain --no-legend 2>/dev/null | grep -c .)
usr=$(systemctl --user --failed --plain --no-legend 2>/dev/null | grep -c .)
total=$((sys + usr))

state=$(systemctl is-system-running 2>/dev/null)
ustate=$(systemctl --user is-system-running 2>/dev/null)
run_sys=$(systemctl list-units --type=service --state=running --no-legend --plain 2>/dev/null | grep -c .)
run_usr=$(systemctl --user list-units --type=service --state=running --no-legend --plain 2>/dev/null | grep -c .)
boot=$(uptime -s 2>/dev/null | cut -c1-16)
fw=$(systemd-analyze 2>/dev/null | head -1 | sed -n 's/.*= *\(.*\)$/\1/p')

tip=""
if (( total > 0 )); then
    tip+="failed units"$'\n'
    tip+=$( { systemctl --failed --plain --no-legend 2>/dev/null | sed 's/^/sys  /';
              systemctl --user --failed --plain --no-legend 2>/dev/null | sed 's/^/usr  /'; } \
            | awk '{u=$2; d=""; for(i=6;i<=NF;i++) d=d (d?" ":"") $i; printf "  %s %s\n      %s\n", $1, u, substr(d,1,40)}')
    tip+=$'\n\n'
fi
tip+="system    ${state:-?}   (${sys} failed)"$'\n'
tip+="user      ${ustate:-?}   (${usr} failed)"$'\n'
tip+="running   ${run_sys} system · ${run_usr} user services"$'\n'
tip+="booted    ${boot}"$'\n'
[ -n "$fw" ] && tip+="boot took ${fw}"$'\n'

timers=$( { systemctl list-timers --no-legend --plain 2>/dev/null;
            systemctl --user list-timers --no-legend --plain 2>/dev/null; } \
  | awk '$1!="-" && $1!="n/a" {for(i=1;i<=NF;i++) if ($i ~ /\.timer$/) {print $2" "$3"\t"$i; break}}' \
  | sort | head -6 | awk -F'\t' '{t=$2; sub(/\.timer$/,"",t); printf "  %s  %s\n", substr($1,6,11), substr(t,1,30)}')
[ -n "$timers" ] && tip+=$'\n'"next timers"$'\n'"${timers}"

if (( total == 0 )); then
    jq -cn --arg tip "$tip" '{text:"", class:"ok", tooltip:$tip}'
else
    jq -cn --arg t "󰀪  $total" --arg tip "$tip" '{text:$t, class:"failed", tooltip:$tip}'
fi
