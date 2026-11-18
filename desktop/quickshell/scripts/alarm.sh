#!/usr/bin/env bash
set -u

id="${1:-alarm-clock-elapsed}"
file="/usr/share/sounds/freedesktop/stereo/${id}.oga"

child=0
trap 'kill -TERM "$child" 2>/dev/null; exit 0' TERM INT

play() {
    "$@" >/dev/null 2>&1 &
    child=$!
    wait "$child"
}

if command -v canberra-gtk-play >/dev/null 2>&1; then
    play canberra-gtk-play -i "$id" && exit 0
fi

[ -r "$file" ] || exit 0

for player in paplay pw-play; do
    command -v "$player" >/dev/null 2>&1 || continue
    play "$player" "$file" && exit 0
done

exit 0
