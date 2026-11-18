#!/usr/bin/env bash
CAVA_CONF="$HOME/.config/quickshell/scripts/cava.conf"
BAR_CHARS=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

BAR_PID=$PPID

CAVA_FIFO="/tmp/qs-cava-$$.fifo"
CAVA_PID=""
cleanup() {
    [ -n "$CAVA_PID" ] && kill -9 "$CAVA_PID" 2>/dev/null
    pkill -9 -P $$ cava 2>/dev/null
    rm -f "$CAVA_FIFO"
}
trap cleanup EXIT

stop_cava() {
    [ -n "$CAVA_PID" ] && kill -9 "$CAVA_PID" 2>/dev/null
    pkill -9 -P $$ cava 2>/dev/null
    rm -f "$CAVA_FIFO"
    CAVA_PID=""
}

find_player() {
    playerctl -l 2>/dev/null | grep -iE '^chrome(\.|$)|^chromium(\.|$)'
}

while true; do
    kill -0 "$BAR_PID" 2>/dev/null || exit 0

    player=""
    for p in $(find_player); do
        status=$(playerctl -p "$p" status 2>/dev/null)
        if [ "$status" = "Playing" ]; then
            player="$p"
            break
        fi
    done

    if [ -z "$player" ]; then
        stop_cava
        echo '{"text":""}'
        sleep 2
        continue
    fi

    meta=$(playerctl -p "$player" metadata --format '{{artist}} — {{title}}' 2>/dev/null)
    meta="${meta# — }"
    [ -z "$meta" ] && meta=$(playerctl -p "$player" metadata --format '{{title}}' 2>/dev/null)
    [ -z "$meta" ] && meta="Playing"

    if [ -z "$CAVA_PID" ] || ! kill -0 "$CAVA_PID" 2>/dev/null; then
        [ -p "$CAVA_FIFO" ] || mkfifo "$CAVA_FIFO"
        cava -p "$CAVA_CONF" > "$CAVA_FIFO" 2>/dev/null &
        CAVA_PID=$!
        exec 3<> "$CAVA_FIFO"
    fi

    if read -r -t 1 -u 3 -a levels; then
        wave=""
        for lvl in "${levels[@]}"; do
            [[ "$lvl" =~ ^[0-9]+$ ]] || lvl=0
            [ "$lvl" -gt 7 ] && lvl=7
            wave+="${BAR_CHARS[$lvl]}"
        done
        max=35
        disp="$meta"
        [ "${#disp}" -gt "$max" ] && disp="${disp:0:$max}…"
        jq -cn --arg t "$wave  $disp" --arg tip "Browser: $meta" \
            '{text:$t, tooltip:$tip, class:["browser-sound","playing-wave"]}'
    fi
done
