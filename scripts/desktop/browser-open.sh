#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# browser-open.sh <url> — open a URL in the default browser, then focus it.
#
#   browser-open.sh <url>   open the URL, then focus the browser
#
# Used wherever the island itself opens a URL (clipboard panel, launcher) in
# place of a bare xdg-open. Deliberately NOT registered as the system-wide
# http(s)/text-html default handler: xdg-settings and xdg-mime read the same
# mimeapps.list entry, so doing that would make browser.sh's own "ask
# xdg-settings which browser to launch" check resolve back to this script --
# infinite recursion, caught live while testing this fix, before it shipped.
#
# Root cause this works around: Wayland's focus-stealing prevention means an
# already-running browser receiving "open this URL" over its own remote-IPC
# can't raise itself. Confirmed live (not guessed): misc:focus_on_activate
# does nothing here (no xdg-activation token is ever presented on this
# path), and even gtk-launch with a URL argument doesn't focus the existing
# window, though it does with no argument. Explicitly focusing by window
# class after the fact is the one approach that worked in every case tried.
set -euo pipefail
dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
"$dir/browser.sh" "$@" &
disown

# The class to focus comes from the real default browser's own .desktop file
# (StartupWMClass -- the same key Hyprland's own window rules use for this)
# instead of guessing a name. Confirmed for Firefox: StartupWMClass=firefox
# matches `hyprctl clients`' reported class exactly.
desktop_id="$(xdg-settings get default-web-browser 2>/dev/null || true)"
cls=""
for d in "$HOME/.local/share/applications" /usr/share/applications /usr/local/share/applications; do
    f="$d/$desktop_id"
    [[ -n $desktop_id && -f $f ]] || continue
    cls="$(sed -n 's/^StartupWMClass=//p' "$f" | head -1)"
    [[ -n $cls ]] && break
done
[[ -n $cls ]] || cls="${desktop_id%.desktop}"
[[ -n $cls ]] || exit 0

# Poll for the window instead of guessing a fixed delay: an already-running
# instance answers almost instantly, a cold start takes longer (but a
# brand-new window gets focus from Hyprland on its own, so giving up early
# there is harmless -- this loop only matters for the already-running case).
for _ in $(seq 1 20); do
    hyprctl clients -j 2>/dev/null | grep -qi "\"class\": *\"$cls\"" && break
    sleep 0.1
done
hyprctl dispatch "hl.dsp.focus({ window = \"class:$cls\" })" >/dev/null 2>&1 || true
