#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Pick an entry from cliphist history with fuzzel and put it back on the clipboard.
set -euo pipefail
pkill -x fuzzel 2>/dev/null && exit 0     # toggle: second press closes
sel="$(cliphist list | fuzzel --dmenu --prompt '󰅌  ' --placeholder 'Clipboard history' --width 70)" || exit 0
printf '%s' "$sel" | cliphist decode | wl-copy
