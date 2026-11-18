#!/usr/bin/env bash
# Deliver a Discord keybind globally on Wayland by briefly focusing Discord,
# injecting a "sacrificial" combo via ydotool, then restoring the previous focus.
#
# Why a sacrificial combo? Hyprland *consumes* any key it binds, so it can never
# also be delivered to a window. The key you press (Alt+I / Alt+;) is the Hyprland
# trigger; the key we inject must be different or it would loop forever and never
# reach Discord. Set these inside Discord (Settings > Keybinds):
#   Toggle Mute   = Ctrl+Alt+Shift+M
#   Toggle Deafen = Ctrl+Alt+Shift+D
#
# Usage: discord-key.sh mute|deafen

set -euo pipefail
export YDOTOOL_SOCKET="${YDOTOOL_SOCKET:-$XDG_RUNTIME_DIR/.ydotool_socket}"

# evdev keycodes (see /usr/include/linux/input-event-codes.h)
CTRL=29; SHIFT=42; ALT=56
case "${1:-}" in
  mute)   K=50 ;;   # KEY_M
  deafen) K=32 ;;   # KEY_D
  *) echo "usage: $0 mute|deafen" >&2; exit 2 ;;
esac

# Locate the Discord window
discord=$(hyprctl clients -j | jq -r 'first(.[] | select(.class|test("discord";"i")) | .address) // empty')
[ -z "$discord" ] && exit 0   # Discord not running; nothing to do

# Remember the window that currently has focus
active=$(hyprctl activewindow -j | jq -r '.address // empty')

# Focus Discord (unless it is already focused)
if [ "$active" != "$discord" ]; then
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$discord\" })" >/dev/null
  sleep 0.12   # let the compositor hand keyboard focus to Discord
fi

# Inject Ctrl+Alt+Shift+<key>  (press in order, release in reverse)
ydotool key ${CTRL}:1 ${ALT}:1 ${SHIFT}:1 ${K}:1 ${K}:0 ${SHIFT}:0 ${ALT}:0 ${CTRL}:0

# Restore the previous focus
if [ -n "$active" ] && [ "$active" != "$discord" ]; then
  sleep 0.03
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$active\" })" >/dev/null
fi
