#!/usr/bin/env bash
icon=$(printf '\U000f035b')

eval "$(awk '/^(MemTotal|MemAvailable|MemFree|Buffers|Cached|SwapTotal|SwapFree|Shmem|Dirty|SReclaimable|AnonPages|Mapped):/ {gsub(":","",$1); printf "%s=%s\n", $1, $2*1024}' /proc/meminfo)"
mu=$((MemTotal - MemAvailable))
g() { awk -v v="$1" 'BEGIN{printf "%.1f", v/1073741824}'; }
pct=$(awk -v u="$mu" -v t="$MemTotal" 'BEGIN{printf "%d", u*100/t}')
cache=$((Cached + Buffers + SReclaimable))
su=$((SwapTotal - SwapFree))

top=$(ps -eo rss=,comm= | awk '{n=$2; for(i=3;i<=NF;i++) n=n" "$i; s[n]+=$1} END{for(n in s) printf "%d\t%s\n", s[n], n}' \
  | sort -rn | head -7 | awk -F'\t' '{printf "  %5.1f GiB  %s\n", $1/1048576, substr($2,1,26)}')

tip="RAM       $(g "$mu") / $(g "$MemTotal") GiB  (${pct}%)"$'\n'
tip+="avail     $(g "$MemAvailable") GiB"$'\n'
tip+="apps      $(g "$AnonPages") GiB"$'\n'
tip+="cache     $(g "$cache") GiB  (reclaimable)"$'\n'
tip+="shared    $(g "$Shmem") GiB"$'\n'
tip+="dirty     $(awk -v v="$Dirty" 'BEGIN{printf "%.0f", v/1048576}') MiB"$'\n'
if [ "${SwapTotal:-0}" -gt 0 ]; then
    tip+="swap      $(g "$su") / $(g "$SwapTotal") GiB"
    dev=$(swapon --noheadings --show=NAME 2>/dev/null | xargs | sed 's#/dev/##g')
    [ -n "$dev" ] && tip+="  (${dev})"
    tip+=$'\n'
fi
tip+=$'\n'"largest (RSS, grouped)"$'\n'"${top}"

if   [ "$pct" -ge 90 ]; then class="crit"
elif [ "$pct" -ge 75 ]; then class="high"
else class="ok"
fi

jq -cn --arg t "${icon}  $(g "$mu")G" --arg tip "$tip" --arg c "$class" \
  '{text:$t, tooltip:$tip, class:$c}'
