#!/usr/bin/env bash
set -euo pipefail

"$HOME/.local/bin/discord-cdp" deafen >/dev/null 2>&1 && exit 0

case "$(qs ipc call island discorddeafen 2>/dev/null | tr -d '[:space:]')" in
  discord) exit 0 ;;
esac

if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED; then
  target=0
else
  target=1
fi

wpctl set-mute @DEFAULT_AUDIO_SOURCE@ "$target"

ids=$(pactl -f json list sink-inputs 2>/dev/null | jq -r '
  .[] | select((.properties["application.process.binary"] // "" | ascii_downcase | test("discord"))) | .index')
for id in $ids; do
  pactl set-sink-input-mute "$id" "$target"
done

if [ "$target" = 1 ]; then
  notify-send -a Discord -t 1200 -h string:x-canonical-private-synchronous:deafen \
    -i audio-volume-muted "Deafened (mic + Discord)"
else
  notify-send -a Discord -t 1200 -h string:x-canonical-private-synchronous:deafen \
    -i audio-volume-high "Un-deafened"
fi
