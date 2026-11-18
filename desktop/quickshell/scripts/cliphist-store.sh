#!/usr/bin/env bash
# cliphist store guard: drops clipboard entries copied out of a password
# manager, forwards everything else unchanged.
# Used as: wl-paste --watch cliphist-store.sh
set -u

DENY_CLASSES="keeper-password-manager keepassxc org.keepassxc.KeePassXC 1password Bitwarden bitwarden dev.goldflag.proton-pass"

drop() { cat >/dev/null; exit 0; }

if wl-paste --list-types 2>/dev/null | grep -qi 'x-kde-passwordManagerHint'; then
    drop
fi

class=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty' 2>/dev/null)
if [ -n "$class" ]; then
    for deny in $DENY_CLASSES; do
        [ "$class" = "$deny" ] && drop
    done
fi

exec cliphist store
