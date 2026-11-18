#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$REPO_ROOT/packages.sh"

require_not_root

WANT_GAMING=${WANT_GAMING:-1}
WANT_OFFICE=${WANT_OFFICE:-1}

enable_multilib() {
    grep -q '^\[multilib\]' /etc/pacman.conf && return 0
    info "Enabling the multilib repository (32-bit game libraries)..."
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
    grep -q '^\[multilib\]' /etc/pacman.conf || die "could not enable [multilib] in /etc/pacman.conf"
    sudo pacman -Sy
}

tune_pacman() {
    sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
    sudo sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
    sudo sed -i 's/^#DisableDownloadTimeout/DisableDownloadTimeout/' /etc/pacman.conf
    note "applied pacman.conf tweaks"
}

PACMAN_PKGS=("${PKG_BASE[@]}")
AUR_PKGS=("${PKG_BASE_AUR[@]}")

if [ "$WANT_GAMING" -eq 1 ]; then
    enable_multilib
    PACMAN_PKGS+=("${PKG_GAMING[@]}")
    AUR_PKGS+=("${PKG_GAMING_AUR[@]}")
fi
if [ "$WANT_OFFICE" -eq 1 ]; then
    PACMAN_PKGS+=("${PKG_OFFICE[@]}")
    AUR_PKGS+=("${PKG_OFFICE_AUR[@]}")
fi

tune_pacman
ensure_aur_helper

info "Installing official packages (${#PACMAN_PKGS[@]})..."
sudo pacman -S --needed "${PACMAN_PKGS[@]}"

info "Installing AUR packages (${#AUR_PKGS[@]})..."
"$AUR_HELPER" -S --needed "${AUR_PKGS[@]}"

info "Installing oh-my-posh (the fish prompt)..."
if [ ! -x "$HOME/.local/bin/oh-my-posh" ]; then
    mkdir -p "$HOME/.local/bin"
    curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
else
    note "oh-my-posh already installed"
fi

if command -v awww >/dev/null 2>&1 && ! command -v swww >/dev/null 2>&1; then
    info "Linking swww -> awww (waypaper backend shim)..."
    sudo ln -sf /usr/bin/awww        /usr/local/bin/swww
    sudo ln -sf /usr/bin/awww-daemon /usr/local/bin/swww-daemon
fi

info "Packages done."
