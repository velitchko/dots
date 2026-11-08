#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Open the default web browser (xdg default, else the first one installed).
if d="$(xdg-settings get default-web-browser 2>/dev/null)" && [[ -n $d ]] && command -v gtk-launch >/dev/null; then
    exec gtk-launch "$d" "$@"
fi
for b in firefox zen-browser librewolf chromium brave vivaldi qutebrowser; do
    command -v "$b" >/dev/null && exec "$b" "$@"
done
notify-send -a Kessel "No web browser installed" "Install one, e.g. sudo pacman -S firefox"
