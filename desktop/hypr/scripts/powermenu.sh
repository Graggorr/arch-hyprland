#!/usr/bin/env bash
# Compact power menu via rofi (small centred window — not fullscreen).
lock=$(printf '\uf023')
logout=$(printf '\uf08b')
suspend=$(printf '\uf186')
reboot=$(printf '\uf021')
shutdown=$(printf '\uf011')

chosen=$(printf '%s  Lock\n%s  Logout\n%s  Suspend\n%s  Reboot\n%s  Shutdown\n' \
            "$lock" "$logout" "$suspend" "$reboot" "$shutdown" \
        | rofi -dmenu -i -p "Power" -theme "$HOME/.config/rofi/powermenu.rasi")

case "$chosen" in
    *Lock)     hyprlock ;;
    *Logout)   uwsm stop ;;
    *Suspend)  systemctl suspend ;;
    *Reboot)   systemctl reboot ;;
    *Shutdown) systemctl poweroff ;;
esac
