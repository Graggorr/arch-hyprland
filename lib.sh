#!/bin/bash

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_SRC="$REPO_ROOT/desktop"
HOME_SRC="$REPO_ROOT/home"
SYSTEM_SRC="$REPO_ROOT/system"

PLACEHOLDER="@HOME@"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/desktop-sync"

info() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '    warn: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

require_not_root() {
    [ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root (sudo is called where needed)"
}

ensure_aur_helper() {
    for h in paru yay; do
        command -v "$h" >/dev/null 2>&1 && { AUR_HELPER="$h"; return 0; }
    done
    info "Installing yay (AUR helper)..."
    sudo pacman -S --needed --noconfirm git base-devel
    rm -rf /tmp/yay-build
    git clone https://aur.archlinux.org/yay.git /tmp/yay-build
    (cd /tmp/yay-build && makepkg -si --noconfirm)
    rm -rf /tmp/yay-build
    AUR_HELPER=yay
}

copy_tree() {
    local src=$1 dest=$2
    [ -d "$src" ] || return 0
    mkdir -p "$dest"
    cp -a "$src/." "$dest/"
}

fill_home() {
    local root=$1 files
    [ -e "$root" ] || return 0
    mapfile -t files < <(grep -rlI -F "$PLACEHOLDER" "$root" 2>/dev/null || true)
    [ "${#files[@]}" -eq 0 ] && return 0
    for f in "${files[@]}"; do
        sed -i "s|$PLACEHOLDER|$HOME|g" "$f"
    done
    note "filled in $HOME in ${#files[@]} file(s)"
}

assert_home_filled() {
    local root=$1 hits
    [ -e "$root" ] || return 0
    hits=$(grep -rlI -F "$PLACEHOLDER" "$root" 2>/dev/null || true)
    [ -z "$hits" ] || die "$PLACEHOLDER survived in:"$'\n'"$hits"
}

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a "Desktop sync" "$1" "${2:-}" 2>/dev/null || true
}

restart_shell_if_safe() {
    mkdir -p "$STATE_DIR"
    if ! pgrep -x qs >/dev/null && ! pgrep -x quickshell >/dev/null; then
        rm -f "$STATE_DIR/restart-pending"
        return 0
    fi
    if [ "$(hyprctl locked 2>/dev/null)" != "false" ]; then
        touch "$STATE_DIR/restart-pending"
        note "shell restart postponed (screen locked or Hyprland unreachable)"
        return 0
    fi
    hyprctl dispatch "hl.dsp.exec_cmd([[$HOME/.local/bin/qs-restart]])" >/dev/null 2>&1 || true
    rm -f "$STATE_DIR/restart-pending"
    note "restarted the shell"
}
