#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Launch OmniGlyph (optional AUR dependency). Fails harmlessly if absent.
if command -v omniglyph >/dev/null 2>&1; then
    exec omniglyph "$@"
fi
notify-send -a Kessel "OmniGlyph not installed" "Optional: ./install.sh --with-aur (yay -S omniglyph)" 2>/dev/null || true
