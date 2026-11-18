#!/usr/bin/env bash
path="$1"
icon="$2"

line=$(df -h --output=used,size,pcent "$path" 2>/dev/null | tail -1)
[ -z "$line" ] && { echo '{"text":""}'; exit 0; }

used=$(echo "$line" | awk '{print $1}')
size=$(echo "$line" | awk '{print $2}')
pcent=$(echo "$line" | awk '{print $3}')
num=${pcent%\%}

if   [ "$num" -ge 92 ]; then class="crit"
elif [ "$num" -ge 85 ]; then class="high"
else class="ok"
fi

jq -cn --arg t "${icon}  ${pcent}" \
       --arg tip "${used} / ${size} used on ${path}   (${pcent})" \
       --arg c "$class" \
       '{text:$t, tooltip:$tip, class:$c}'
