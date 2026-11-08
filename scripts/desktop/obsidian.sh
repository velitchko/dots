#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Obsidian, if installed (official package `obsidian`).
command -v obsidian >/dev/null || { notify-send -a Kessel "Obsidian is not installed" "sudo pacman -S obsidian"; exit 0; }
exec obsidian "$@"
