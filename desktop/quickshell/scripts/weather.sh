#!/usr/bin/env bash
# Weather from sinoptik.ua (Foreca data) for the island's pill and tool.
# Emits {text,tooltip,class,icon,hex,temp,feels,desc,area,humidity,wind,uv,
# sunrise,sunset,forecast[]} — 10 forecast days. Cached 30 min; on any failure
# the previous reading is reused rather than blanking the pill.
CITY="${1:-kyiv}"
CACHE="/tmp/qs-weather.json"
SUNFILE="/tmp/qs-sun"
TTL=1800

now=$(date +%s)
if [ -f "$CACHE" ] && [ $((now - $(stat -c %Y "$CACHE"))) -lt "$TTL" ]; then
    cat "$CACHE"; exit 0
fi

UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
html=$(curl -sL --compressed --max-time 12 -A "$UA" \
       "https://sinoptik.ua/pohoda/${CITY}/10-dniv" 2>/dev/null)

out=$(printf '%s' "$html" | CITY="$CITY" python3 @HOME@/.config/quickshell/scripts/weather-parse.py 2>/tmp/qs-sun-raw)

if [ -n "$out" ] && printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    [ -s /tmp/qs-sun-raw ] && cp /tmp/qs-sun-raw "$SUNFILE"
    printf '%s\n' "$out" | tee "$CACHE"
    exit 0
fi

[ -f "$CACHE" ] && { cat "$CACHE"; exit 0; }
jq -cn --arg t "$(printf '')  n/a" \
    '{text:$t, tooltip:"weather unavailable", class:"weather", icon:"", hex:"#aab3c2",
      temp:"--", feels:"", desc:"unavailable", area:"", humidity:"",
      wind:"", uv:"", sunrise:"", sunset:"", forecast:[]}'
