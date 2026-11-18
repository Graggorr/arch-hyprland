#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_not_root

UNIT_DIR="$HOME/.config/systemd/user"

info "Installing the desktop-sync timer..."
mkdir -p "$UNIT_DIR"

cat > "$UNIT_DIR/desktop-sync.service" <<UNIT
[Unit]
Description=Pull the desktop config from the repo and patch it in
After=network-online.target

[Service]
Type=oneshot
ExecStart=$REPO_ROOT/update.sh
UNIT

cat > "$UNIT_DIR/desktop-sync.timer" <<'UNIT'
[Unit]
Description=Keep the desktop config in step with the repo

[Timer]
OnStartupSec=3min
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now desktop-sync.timer 2>/dev/null \
    && note "enabled desktop-sync.timer (3 min after login, then hourly)" \
    || warn "could not enable desktop-sync.timer — run: systemctl --user enable --now desktop-sync.timer"

if ! GIT_TERMINAL_PROMPT=0 git -C "$REPO_ROOT" ls-remote --exit-code origin HEAD >/dev/null 2>&1; then
    warn "this clone cannot fetch unattended — re-clone it from https://github.com/Graggorr/arch-hyprland.git"
fi

info "Sync done."
