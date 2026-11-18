#!/usr/bin/env bash
# Apply GTK / cursor theming at session start (replaces ML4W's gtk.sh).
# Values mirror ~/.config/gtk-3.0/settings.ini so apps look consistent.
gnome_schema="org.gnome.desktop.interface"
gsettings set "$gnome_schema" gtk-theme    "Breeze-Dark"
gsettings set "$gnome_schema" icon-theme   "Tela-native"
gsettings set "$gnome_schema" cursor-theme "phinger-cursors-dark"
gsettings set "$gnome_schema" cursor-size  24
gsettings set "$gnome_schema" font-name    "Fira Sans Semi-Bold 11"
gsettings set "$gnome_schema" color-scheme "prefer-dark"

hyprctl setcursor phinger-cursors-dark 24

"$HOME/.local/bin/icon-theme-sync" >/dev/null 2>&1 &
