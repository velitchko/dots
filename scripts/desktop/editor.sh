#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Code editor: Neovim in kitty.
command -v nvim >/dev/null || { notify-send -a Kessel "Neovim is not installed" "sudo pacman -S neovim"; exit 0; }
exec kitty --class nvim -e nvim "$@"
