#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Pick a colour on screen → clipboard (#RRGGBB) + notification.
command -v hyprpicker >/dev/null || { notify-send -a "Color picker" "hyprpicker is not installed" "sudo pacman -S hyprpicker"; exit 0; }
c="$(hyprpicker -a -f hex 2>/dev/null)" || exit 0
[[ -n $c ]] && notify-send -a "Color picker" "$c" "Copied to clipboard"
