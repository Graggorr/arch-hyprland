#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_not_root

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

info "Preparing dotfiles for $HOME..."
copy_tree "$HOME_SRC" "$STAGE"
fill_home "$STAGE"
assert_home_filled "$STAGE"

BACKUP="$HOME/.config/.desktop-backups/$(date +%Y%m%d-%H%M%S)-dotfiles"
replaced=0
while IFS= read -r -d '' f; do
    rel="${f#"$STAGE"/}"
    if [ -f "$HOME/$rel" ] && ! cmp -s "$f" "$HOME/$rel"; then
        mkdir -p "$BACKUP/$(dirname "$rel")"
        cp -a "$HOME/$rel" "$BACKUP/$rel"
        replaced=$((replaced + 1))
    fi
done < <(find "$STAGE" -type f -print0)
[ "$replaced" -gt 0 ] && note "$replaced existing file(s) saved to $BACKUP"

info "Installing dotfiles..."
cp -a "$STAGE/." "$HOME/"
chmod +x "$HOME/.local/bin/"* 2>/dev/null || true
note "installed ~/.config, ~/.local/bin, ~/.local/share/applications"

if [ -f "$HOME/.bashrc_custom" ] && ! grep -q "bashrc_custom" "$HOME/.bashrc" 2>/dev/null; then
    {
        echo ""
        echo "# Load user customizations"
        echo "[ -f ~/.bashrc_custom ] && source ~/.bashrc_custom"
    } >> "$HOME/.bashrc"
    note "hooked ~/.bashrc_custom into ~/.bashrc"
fi

mkdir -p "$HOME"/{Desktop,Documents,Downloads,Music,Pictures,Public,Templates,Videos}
command -v xdg-user-dirs-update >/dev/null 2>&1 && xdg-user-dirs-update
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
systemctl --user daemon-reload 2>/dev/null || true

info "Dotfiles done."
