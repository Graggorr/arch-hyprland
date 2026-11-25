#!/usr/bin/env bash
# What hypridle's 60-minute listener does: sleep | off.
# Usage: idle-mode.sh get | set <mode> | cycle | timeout | resume
# get -> {"mode":"sleep|off","label":"...","glyph":"..."}
set -u

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
STATE="$STATE_DIR/idle-mode"

read_mode() {
    local m
    m=$(cat "$STATE" 2>/dev/null)
    case "$m" in
        sleep|off) printf '%s' "$m" ;;
        dpms) printf 'off' ;;
        *) printf 'sleep' ;;
    esac
}

emit() {
    local m glyph label
    m=$(read_mode)
    case "$m" in
        sleep) glyph=$'\U000f04b2'; label="Sleep after 1h" ;;
        off)   glyph=$'\U000f0904'; label="Stay awake" ;;
    esac
    jq -cn --arg m "$m" --arg l "$label" --arg g "$glyph" \
        '{mode:$m, label:$l, glyph:$g}'
}

case "${1:-get}" in
    get) emit ;;
    set)
        case "${2:-}" in
            sleep|off)
                mkdir -p "$STATE_DIR"
                printf '%s' "$2" > "$STATE"
                emit
                ;;
            *) echo '{"error":"mode must be sleep or off"}' >&2; exit 1 ;;
        esac
        ;;
    cycle)
        case "$(read_mode)" in
            sleep) next=off ;;
            *)     next=sleep ;;
        esac
        mkdir -p "$STATE_DIR"
        printf '%s' "$next" > "$STATE"
        emit
        ;;
    timeout)
        case "$(read_mode)" in
            sleep) systemctl suspend ;;
        esac
        ;;
    resume)
        hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
        ;;
    *)
        echo "usage: idle-mode.sh get | set <sleep|off> | cycle | timeout | resume" >&2
        exit 1
        ;;
esac
