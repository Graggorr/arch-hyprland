#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_not_root

WANT_GAMING=1
WANT_OFFICE=1
STEPS=()

usage() {
    cat <<'USAGE'
usage: ./install.sh [options] [step ...]

steps:   packages  desktop  dotfiles  system  sync     (default: all, in this order)

options:
  --no-gaming    skip Steam, gamescope, gamemode and the 32-bit multilib repo
  --no-office    skip LibreOffice, the PDF viewer and printing support
  -h, --help     show this
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --no-gaming) WANT_GAMING=0 ;;
        --no-office) WANT_OFFICE=0 ;;
        -h|--help)   usage; exit 0 ;;
        packages|desktop|dotfiles|system|sync) STEPS+=("$arg") ;;
        *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

[ "${#STEPS[@]}" -eq 0 ] && STEPS=(packages desktop dotfiles system sync)

export WANT_GAMING WANT_OFFICE

for step in "${STEPS[@]}"; do
    "$REPO_ROOT/install-$step.sh"
done

cat <<NEXT

==> Done.

    Log out and pick the "Hyprland (uwsm-managed)" session at the SDDM
    login screen, or reboot.

    First things to do in the new session:
      Super + /        the shortcut cheatsheet, everything else is in there
      Super + W        pick a wallpaper (the whole colour scheme follows it)
      Super + space    the app launcher

    Not done automatically:
      - Set a keyboard layout you actually use: kb_layout in
        ~/.config/hypr/hyprland.lua (currently "us,ua", Ctrl+Shift switches).
      - Sign in to Brave, Telegram, Discord, Spotify and Claude.
      - Steam downloads Proton on first launch of a Windows game.

    The desktop config follows the repo from now on: desktop-sync.timer
    pulls and patches it in hourly. Run ./update.sh to do it now.
NEXT
