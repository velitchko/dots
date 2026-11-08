#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Fallback for SUPER+/ when the island isn't running (it has a Shortcuts panel):
# the shortcuts generated from keybinds.lua (written on every config load).
set -euo pipefail
pkill -x fuzzel 2>/dev/null && exit 0
f="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/kessel-shortcuts.txt"
[[ -r $f ]] || { notify-send "Shortcuts" "No shortcuts file yet — reload Hyprland (SUPER+CTRL+R)"; exit 0; }
# Nerd Font *Mono*: every key icon is one cell wide, so the columns line up.
# Medium weight: fuzzel draws the regular weight visibly thinner than the island (Qt).
fuzzel --dmenu --font 'JetBrainsMono Nerd Font Mono:size=13:weight=medium' \
    --prompt $'\uf303  ' --placeholder 'Search shortcuts' --width 72 --lines 20 < "$f" >/dev/null || true
