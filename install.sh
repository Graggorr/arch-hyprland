#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_not_root

WANT_GAMING=1
WANT_OFFICE=1
WANT_UPDATES=1
STEPS=()

usage() {
    cat <<'USAGE'
usage: ./install.sh [options] [step ...]

steps:   packages  desktop  dotfiles  system  sync     (default: all, in this order)

options:
  --no-gaming    skip Steam, gamescope, gamemode and the 32-bit multilib repo
  --no-office    skip LibreOffice, the PDF viewer and printing support
  --no-updates   do not install the hourly desktop updater (turn it on later with ./update.sh --on)
  -h, --help     show this
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --no-gaming) WANT_GAMING=0 ;;
        --no-office) WANT_OFFICE=0 ;;
        --no-updates) WANT_UPDATES=0 ;;
        -h|--help)   usage; exit 0 ;;
        packages|desktop|dotfiles|system|sync) STEPS+=("$arg") ;;
        *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "${#STEPS[@]}" -eq 0 ]; then
    STEPS=(packages desktop dotfiles system)
    [ "$WANT_UPDATES" -eq 1 ] && STEPS+=(sync)
fi

export WANT_GAMING WANT_OFFICE

for step in "${STEPS[@]}"; do
    "$REPO_ROOT/install-$step.sh"
done

if systemctl --user is-enabled desktop-sync.timer >/dev/null 2>&1; then
    UPDATES_NOTE="    The desktop config follows the repo from now on: desktop-sync.timer
    pulls and patches it in hourly (Settings > General > Desktop updates,
    or ./update.sh --off, turns that off). ./update.sh updates right now."
else
    UPDATES_NOTE="    Automatic updates are off: this desktop is yours to change and stays
    exactly as it is. ./update.sh --on turns them on."
fi

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

$UPDATES_NOTE
NEXT
