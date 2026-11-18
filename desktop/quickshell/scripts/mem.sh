#!/usr/bin/env bash
icon=$(printf '\U000f035b')

eval "$(free -b | awk '
/^Mem:/  { printf "mt=%s mu=%s ma=%s ", $2, $3, $7 }
/^Swap:/ { printf "st=%s su=%s", $2, $3 }
')"

g() { awk -v v="$1" 'BEGIN{printf "%.1f", v/1073741824}'; }
pct=$(awk -v u="$mu" -v t="$mt" 'BEGIN{printf "%d", u*100/t}')

tip="RAM   $(g "$mu") / $(g "$mt") GiB   (${pct}%)
Avail $(g "$ma") GiB"
if [ "${st:-0}" -gt 0 ]; then
    tip="${tip}
Swap  $(g "$su") / $(g "$st") GiB"
fi

if   [ "$pct" -ge 90 ]; then class="crit"
elif [ "$pct" -ge 75 ]; then class="high"
else class="ok"
fi

jq -cn --arg t "${icon}  $(g "$mu")G" --arg tip "$tip" --arg c "$class" \
  '{text:$t, tooltip:$tip, class:$c}'
