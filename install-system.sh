#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_not_root

WANT_GAMING=${WANT_GAMING:-1}

info "Setting the locale..."
if [ -f "$SYSTEM_SRC/locale.gen" ]; then
    sudo cp "$SYSTEM_SRC/locale.gen" /etc/locale.gen
    sudo locale-gen
    printf 'LANG=en_US.UTF-8\n' | sudo tee /etc/locale.conf >/dev/null
    note "locale set to en_US.UTF-8"
fi

info "Restoring udev rules..."
if [ -d "$SYSTEM_SRC/udev/rules.d" ]; then
    sudo cp "$SYSTEM_SRC/udev/rules.d/"*.rules /etc/udev/rules.d/
    sudo udevadm control --reload 2>/dev/null || true
    sudo udevadm trigger --action=add --subsystem-match=powercap 2>/dev/null || true
    note "restored /etc/udev/rules.d/ (CPU power readings for the monitoring tool)"
fi

info "Wiring systemd-oomd to the desktop session..."
OOMD="$SYSTEM_SRC/systemd/user-.slice.d/oomd.conf"
if [ -f "$OOMD" ]; then
    sudo mkdir -p /etc/systemd/system/user-.slice.d
    sudo cp "$OOMD" /etc/systemd/system/user-.slice.d/oomd.conf
    sudo systemctl daemon-reload
    sudo systemctl enable --now systemd-oomd.service 2>/dev/null && note "enabled systemd-oomd.service"
fi

if [ "$WANT_GAMING" -eq 1 ]; then
    NICE="$SYSTEM_SRC/systemd/user@.service.d/10-nice-limit.conf"
    if [ -f "$NICE" ]; then
        sudo mkdir -p /etc/systemd/system/user@.service.d
        sudo cp "$NICE" /etc/systemd/system/user@.service.d/10-nice-limit.conf
        sudo systemctl daemon-reload
        note "granted the user manager LimitNICE=-10 (gamemode renice; needs a re-login)"
    fi
    if command -v gamemoded >/dev/null 2>&1; then
        id -nG | tr ' ' '\n' | grep -qx gamemode || sudo usermod -aG gamemode "$USER"
        systemctl --user enable --now gamemoded.service 2>/dev/null && note "enabled gamemoded.service"
    fi
fi

info "Enabling system services..."
for unit in NetworkManager bluetooth sddm; do
    sudo systemctl enable "$unit" 2>/dev/null && note "enabled $unit" || warn "could not enable $unit"
done
sudo systemctl enable --now power-profiles-daemon.service 2>/dev/null || true
if command -v cupsd >/dev/null 2>&1; then
    sudo systemctl enable --now cups.socket 2>/dev/null && note "enabled cups.socket (printing)"
fi

if systemctl --user is-enabled swaync.service >/dev/null 2>&1; then
    systemctl --user disable --now swaync.service 2>/dev/null \
        && note "disabled swaync.service (quickshell owns notifications)"
fi

info "System done."
