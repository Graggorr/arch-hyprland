#!/usr/bin/env bash
# Clipboard history picker: select with rofi, copy, then auto-paste into the
# window that was focused when the picker was invoked.

# Capture the target before rofi opens (rofi is a layer surface, but be safe)
target=$(hyprctl activewindow -j)
addr=$(jq -r '.address' <<<"$target")
class=$(jq -r '.class' <<<"$target" | tr '[:upper:]' '[:lower:]')

selection=$(cliphist list | rofi -dmenu -i -p "clipboard") || exit 0
[ -z "$selection" ] && exit 0

printf '%s' "$selection" | cliphist decode | wl-copy

# Give rofi time to close and focus to return
sleep 0.2

# Terminals paste with Ctrl+Shift+V; everything else with Ctrl+V
case "$class" in
    com.mitchellh.ghostty|kitty|alacritty|foot|org.wezfurlong.wezterm|konsole|org.kde.konsole)
        hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"CTRL SHIFT\", key = \"V\", window = \"address:$addr\" })" ;;
    *)
        hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"CTRL\", key = \"V\", window = \"address:$addr\" })" ;;
esac
