#!/usr/bin/env bash
set -uo pipefail

state_dir="${XDG_RUNTIME_DIR:-/tmp}/quickshell-gamemode"
bg_weight=20

profile_get() { powerprofilesctl get 2>/dev/null; }

gm_registered() {
    command -v gamemoded >/dev/null 2>&1 || return 1
    timeout 5 gamemoded -s"$1" 2>/dev/null | grep -q 'registered'
}

gm_register() {
    command -v gamemoded >/dev/null 2>&1 || return 0
    [ -d "/proc/$1" ] || return 0
    gm_registered "$1" && return 0
    timeout 5 gamemoded -r"$1" >/dev/null 2>&1
    printf '%s\n' "$1" >"$state_dir/gmpid"
}

gm_unregister() {
    local pid
    [ -r "$state_dir/gmpid" ] || return 0
    pid=$(cat "$state_dir/gmpid")
    rm -f "$state_dir/gmpid"
    [ -n "$pid" ] && [ -d "/proc/$pid" ] || return 0
    gm_registered "$pid" || return 0
    timeout 5 gamemoded -r"$pid" >/dev/null 2>&1
}

case ${1:-} in
on)
    mkdir -p "$state_dir"
    systemctl --user --runtime set-property app.slice CPUWeight="$bg_weight" >/dev/null 2>&1
    [ "${2:-0}" -gt 0 ] 2>/dev/null && gm_register "$2"
    cur=$(profile_get)
    if [ -n "$cur" ] && [ "$cur" != performance ]; then
        printf '%s\n' "$cur" >"$state_dir/profile"
        powerprofilesctl set performance >/dev/null 2>&1
    fi
    ;;
off)
    gm_unregister
    systemctl --user --runtime set-property app.slice CPUWeight= >/dev/null 2>&1
    if [ -r "$state_dir/profile" ]; then
        prev=$(cat "$state_dir/profile")
        [ "$(profile_get)" = performance ] && powerprofilesctl set "$prev" >/dev/null 2>&1
        rm -f "$state_dir/profile"
    fi
    ;;
status)
    cg="/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service"
    gmpid=$(cat "$state_dir/gmpid" 2>/dev/null || echo none)
    printf 'app.slice CPUWeight=%s session.slice CPUWeight=%s profile=%s saved=%s gamemode_pid=%s nice=%s\n' \
        "$(cat "$cg/app.slice/cpu.weight" 2>/dev/null)" \
        "$(cat "$cg/session.slice/cpu.weight" 2>/dev/null)" \
        "$(profile_get)" \
        "$(cat "$state_dir/profile" 2>/dev/null || echo none)" \
        "$gmpid" \
        "$([ "$gmpid" != none ] && ps -o ni= -p "$gmpid" 2>/dev/null | tr -d ' ' || echo -)"
    ;;
*)
    printf 'usage: %s on [pid]|off|status\n' "${0##*/}" >&2
    exit 2
    ;;
esac
