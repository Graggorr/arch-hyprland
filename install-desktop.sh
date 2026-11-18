#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_not_root

MODE=fresh
case "${1:-}" in
    "")       MODE=fresh ;;
    --update) MODE=update ;;
    --check)  MODE=check ;;
    *) die "usage: install-desktop.sh [--update|--check]" ;;
esac

DE_DIRS=(hypr quickshell rofi wlogout waypaper matugen)

verify_lua() {
    command -v Hyprland >/dev/null 2>&1 || return 0
    Hyprland --verify-config -c "$1" 2>&1 | grep -q '^config ok'
}

build_desktop() {
    local dest=$1 d
    for d in "${DE_DIRS[@]}"; do
        copy_tree "$DESKTOP_SRC/$d" "$dest/$d"
    done
    fill_home "$dest"
    assert_home_filled "$dest"
    chmod +x "$dest/hypr/scripts/"* 2>/dev/null || true
    chmod +x "$dest/quickshell/scripts/"*.sh "$dest/quickshell/scripts/"*.py 2>/dev/null || true
    verify_lua "$dest/hypr/hyprland.lua" \
        || die "hyprland.lua failed verification — run: Hyprland --verify-config -c $dest/hypr/hyprland.lua"
    note "hyprland.lua verified: config ok"
}

backup_existing() {
    local stamp bdir moved=0
    stamp="$(date +%Y%m%d-%H%M%S)"
    bdir="$HOME/.config/.desktop-backups/$stamp"
    for d in "${DE_DIRS[@]}"; do
        if [ -e "$HOME/.config/$d" ]; then
            mkdir -p "$bdir"
            mv "$HOME/.config/$d" "$bdir/$d"
            moved=1
        fi
    done
    [ "$moved" -eq 1 ] && note "previous config moved to $bdir"
    return 0
}

record_applied() {
    mkdir -p "$STATE_DIR"
    rm -rf "$STATE_DIR/base"
    cp -a "$STAGE" "$STATE_DIR/base"
    git -C "$REPO_ROOT" rev-parse HEAD > "$STATE_DIR/applied" 2>/dev/null || true
}

render_palette() {
    python3 "$HOME/.config/hypr/scripts/wallpapers.py" theme >/dev/null 2>&1 || true
}

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

if [ "$MODE" = check ]; then
    export HOME=/home/desktop-check
    info "Building the desktop into a scratch directory..."
    build_desktop "$STAGE"
    info "Check passed: this commit builds for another user."
    exit 0
fi

if [ "$MODE" = update ]; then
    info "Building the desktop config from the repo..."
    build_desktop "$STAGE"

    info "Patching ~/.config..."
    BACKUP="$HOME/.config/.desktop-backups/$(date +%Y%m%d-%H%M%S)-update"
    CHANGES="$STAGE.changes"
    trap 'rm -rf "$STAGE" "$CHANGES"' EXIT
    python3 "$REPO_ROOT/sync-desktop.py" "$STAGE" "$STATE_DIR/base" "$HOME/.config" "$BACKUP" > "$CHANGES"
    sed 's/^/    /' "$CHANGES"

    if ! verify_lua "$HOME/.config/hypr/hyprland.lua"; then
        mkdir -p "$BACKUP/hypr"
        cp -a "$HOME/.config/hypr/hyprland.lua" "$BACKUP/hypr/hyprland.lua.rejected"
        cp -a "$STAGE/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua"
        printf 'conflict\thypr/hyprland.lua\n' >> "$CHANGES"
        warn "merged hyprland.lua did not verify — took the repo version, local copy in $BACKUP"
    fi

    record_applied

    if [ ! -s "$CHANGES" ]; then
        note "nothing to patch"
        exit 0
    fi

    if cut -f2 "$CHANGES" | grep -qE '^(matugen/|hypr/themes\.json|hypr/scripts/wallpapers\.py)'; then
        render_palette
        note "palette re-rendered"
    fi
    if cut -f2 "$CHANGES" | grep -q '^hypr/'; then
        hyprctl reload >/dev/null 2>&1 && note "reloaded Hyprland"
    fi
    if cut -f2 "$CHANGES" | grep -q '^quickshell/'; then
        restart_shell_if_safe
    fi
    if grep -q '^conflict' "$CHANGES"; then
        notify "Desktop updated" "Some local edits were replaced; copies are in $BACKUP"
    fi

    info "Desktop updated ($(wc -l < "$CHANGES") file(s))."
    exit 0
fi

info "Building the desktop config from the repo..."
build_desktop "$STAGE"

info "Laying down the desktop config..."
backup_existing
mkdir -p "$HOME/.config"
for d in "${DE_DIRS[@]}"; do
    copy_tree "$STAGE/$d" "$HOME/.config/$d"
done
record_applied

WALLPAPERS="$HOME/Pictures/Wallpapers"
mkdir -p "$WALLPAPERS"
if [ -z "$(ls -A "$WALLPAPERS" 2>/dev/null)" ] && [ -d /usr/share/backgrounds/archlinux ]; then
    cp /usr/share/backgrounds/archlinux/*.jpg "$WALLPAPERS/" 2>/dev/null || true
    cp /usr/share/backgrounds/archlinux/*.png "$WALLPAPERS/" 2>/dev/null || true
    note "seeded $WALLPAPERS from the archlinux-wallpaper package"
fi

mkdir -p "$HOME/.config"/{rofi,quickshell,hypr,wlogout,gtk-3.0,gtk-4.0}

info "Generating the colour palette..."
render_palette
if [ -s "$HOME/.config/quickshell/colors.css" ]; then
    note "palette generated from the current wallpaper"
elif command -v matugen >/dev/null 2>&1 && matugen color hex '#a1c9fd' --mode dark >/dev/null 2>&1; then
    note "palette seeded from the fallback accent (no wallpaper set yet)"
else
    warn "palette not generated — it lands on the first wallpaper change (Super+W)"
fi

info "Desktop done."
