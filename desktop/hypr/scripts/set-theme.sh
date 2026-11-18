#!/usr/bin/env bash
set -u

if [ -n "${1:-}" ]; then
    exec python3 "$HOME/.config/hypr/scripts/wallpapers.py" import-waypaper
fi

exec python3 "$HOME/.config/hypr/scripts/wallpapers.py" theme
