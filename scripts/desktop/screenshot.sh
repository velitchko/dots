#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# screenshot.sh region|full — save to ~/Pictures/Screenshots and copy to clipboard.
set -euo pipefail
mode="${1:-region}"
dir="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots"
mkdir -p "$dir"
file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
case "$mode" in
    region) geom="$(slurp -d)" || exit 0   # Esc cancels quietly
            grim -g "$geom" "$file" ;;
    full)   grim "$file" ;;
    *)      echo "usage: $0 region|full" >&2; exit 2 ;;
esac
wl-copy --type image/png < "$file"
# image-path (not -i, which only sets the small app_icon and Quickshell's
# iconPath() expects a theme name, not a raw path) is what the island's
# NotificationCard actually renders as the big thumbnail. x-kessel-open-path
# is a custom hint it also reads: click the card to open Dolphin on the file.
notify-send -a Screenshot -h "string:image-path:file://$file" -h "string:x-kessel-open-path:$file" \
    "Screenshot saved" "${file/#$HOME/\~} (copied)" || true
