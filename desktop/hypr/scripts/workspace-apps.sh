#!/usr/bin/env bash

set -u

sleep 1

for _ in $(seq 1 100); do
    gdbus introspect --session --dest org.kde.StatusNotifierWatcher \
        --object-path /StatusNotifierWatcher >/dev/null 2>&1 && break
    sleep 0.2
done

command -v nm-online >/dev/null 2>&1 && nm-online -q -s -t 60

spawn() {
    local bin=$1 proc=$2 cmd=$3
    command -v "$bin" >/dev/null 2>&1 || return 0
    pgrep -x "$proc" >/dev/null && return 0
    hyprctl dispatch "hl.dsp.exec_cmd([[$cmd]])"
    sleep 1.5
}

spawn Telegram Telegram '/usr/bin/Telegram'
spawn spotify  spotify  '/usr/bin/spotify'
