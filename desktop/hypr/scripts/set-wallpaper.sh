#!/usr/bin/env bash
set -u

WP="${1:-}"
OUT="${2:-all}"
[ -z "$WP" ] && { echo "usage: set-wallpaper.sh /path/to/image [output|all]"; exit 1; }

exec python3 "$HOME/.config/hypr/scripts/wallpapers.py" set "$OUT" "$WP"
