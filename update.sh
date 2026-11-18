#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_not_root

FORCE=0
case "${1:-}" in
    "")      ;;
    --force) FORCE=1 ;;
    --off)
        systemctl --user disable --now desktop-sync.timer 2>/dev/null || true
        note "automatic desktop updates are off — your config stays exactly as it is"
        note "update by hand any time with ./update.sh, or turn them back on with ./update.sh --on"
        exit 0 ;;
    --on)
        [ -f "$HOME/.config/systemd/user/desktop-sync.timer" ] || "$REPO_ROOT/install-sync.sh"
        systemctl --user enable --now desktop-sync.timer
        note "automatic desktop updates are on (3 min after login, then hourly) from $(git -C "$REPO_ROOT" remote get-url origin)"
        exit 0 ;;
    --status)
        state="$(systemctl --user is-enabled desktop-sync.timer 2>/dev/null || echo off)"
        note "automatic updates: $state · source: $(git -C "$REPO_ROOT" remote get-url origin)"
        exit 0 ;;
    *) die "usage: update.sh [--force | --off | --on | --status]" ;;
esac

fail() {
    notify "Desktop update failed" "$1"
    die "$1"
}

mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/lock"
flock -n 9 || { note "another update is running"; exit 0; }

if ! git -C "$REPO_ROOT" fetch --quiet origin; then
    warn "could not reach the repo — trying again on the next run"
    exit 0
fi
git -C "$REPO_ROOT" merge --quiet --ff-only '@{u}' \
    || fail "the repo clone in $REPO_ROOT has local changes and cannot fast-forward"

HEAD_NOW="$(git -C "$REPO_ROOT" rev-parse HEAD)"
APPLIED="$(cat "$STATE_DIR/applied" 2>/dev/null || true)"

if [ "$FORCE" -eq 0 ] && [ -n "$APPLIED" ] && [ -d "$STATE_DIR/base" ] \
    && git -C "$REPO_ROOT" diff --quiet "$APPLIED" "$HEAD_NOW" -- desktop install-desktop.sh lib.sh sync-desktop.py 2>/dev/null; then
    printf '%s\n' "$HEAD_NOW" > "$STATE_DIR/applied"
    [ -e "$STATE_DIR/restart-pending" ] && restart_shell_if_safe
    note "desktop config is up to date"
    exit 0
fi

exec "$REPO_ROOT/install-desktop.sh" --update
