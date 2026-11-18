#!/usr/bin/env bash
set -euo pipefail

"$HOME/.local/bin/discord-cdp" mute >/dev/null 2>&1 && exit 0

case "$(qs ipc call island discordmute 2>/dev/null | tr -d '[:space:]')" in
  discord|stream) exit 0 ;;
esac

wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle

if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED; then
  notify-send -a Mic -t 1200 -h string:x-canonical-private-synchronous:mic \
    -i microphone-sensitivity-muted "Mic muted"
else
  notify-send -a Mic -t 1200 -h string:x-canonical-private-synchronous:mic \
    -i microphone-sensitivity-high "Mic on"
fi
