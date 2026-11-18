#!/usr/bin/env bash
set -euo pipefail

read -r idx count keymap < <(hyprctl devices -j | jq -r '
  [.keyboards[]] as $k
  | ($k | group_by(.active_layout_index) | max_by(length)[0]) as $m
  | "\($m.active_layout_index) \($k | map(.layout | split(",") | length) | max) \($m.active_keymap)"')

case "${1:-get}" in
  get)  printf '%s\n' "$keymap" ;;
  next) hyprctl switchxkblayout all $(( (idx + 1) % count )) >/dev/null ;;
  prev) hyprctl switchxkblayout all $(( (idx + count - 1) % count )) >/dev/null ;;
esac
