#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ~/Scripts/sddm-theme.sh — the Kessel login screen (matches the lock screen).
#
#   sddm-theme.sh test        preview in a window (no root, changes nothing)
#   sddm-theme.sh install     copy theme + current wallpaper + ~/.face, select it (sudo)
#   sddm-theme.sh uninstall   back to SDDM's default theme (sudo)
#   …add --dry-run to install/uninstall to only print the commands
#
# System files touched (only by install/uninstall):
#   /usr/share/sddm/themes/kessel/        theme
#   /usr/share/sddm/faces/$USER.face.icon avatar (from ~/.face, if present)
#   /etc/sddm.conf.d/10-kessel.conf       [Theme] Current=kessel (+ cursor), and on HiDPI
#                                         [General] GreeterEnvironment=QT_SCALE_FACTOR=<Hyprland's scale>
#   /etc/sddm.conf                        [Theme] Current=kessel, only if the key is already
#                                         present — some SDDM builds let this file outrank
#                                         /etc/sddm.conf.d/*.conf (seen on 0.21: a theme
#                                         installed outside these dots had left Current=
#                                         pointed elsewhere here, and it silently won)
# Existing files are backed up to *.kessel-bak-<ts> first.
# Recovery over SSH if the login screen ever misbehaves:
#   sudo rm /etc/sddm.conf.d/10-kessel.conf   (takes effect at the next greeter start)
#   also check /etc/sddm.conf's [Theme] Current= — it can override the above
set -euo pipefail
repo="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
source "$repo/installer/common.sh"
src="$repo/sddm-theme/kessel"
shapes="$repo/.config/quickshell/kessel-lock/ShapeChar.qml"   # password shapes, shared with the lock screen
dest=/usr/share/sddm/themes/kessel
conf=/etc/sddm.conf.d/10-kessel.conf
ts="$(date +%Y%m%d-%H%M%S)"

cmd=${1:-}; shift || true
[[ ${1:-} == --dry-run ]] && DRY_RUN=1

wallpaper() { jq -r '.wallpaper // empty' "${XDG_STATE_HOME:-$HOME/.local/state}/kessel/theme/colors.json" 2>/dev/null || true; }
accent()    { jq -r '.accent // "#8aadf4"' "${XDG_STATE_HOME:-$HOME/.local/state}/kessel/theme/colors.json" 2>/dev/null || echo "#8aadf4"; }

if [[ $cmd == install || $cmd == test ]] && ! command -v sddm-greeter-qt6 >/dev/null 2>&1; then
    die "SDDM (with its Qt6 greeter) is not installed: sudo pacman -S sddm — and enable it yourself if wanted"
fi

case $cmd in
    test)
        # preview a throwaway copy carrying the current wallpaper + theme colours
        t="$(mktemp -d)"; cp -r "$src/." "$t/"; cp "$shapes" "$t/"
        w="$(wallpaper)"; [[ -r $w ]] && { rm -f "$t"/background.*; cp "$w" "$t/background.${w##*.}"; sed -i "s|^background=.*|background=background.${w##*.}|" "$t/theme.conf"; }
        tc="${XDG_STATE_HOME:-$HOME/.local/state}/kessel/theme/colors.json"
        for k in accent mode text red; do v="$(jq -r --arg k "$k" '.[$k] // empty' "$tc" 2>/dev/null || true)"; [[ -n $v ]] && sed -i "s|^$k=.*|$k=$v|" "$t/theme.conf"; done
        v="$(jq -r '.bg // empty' "$tc" 2>/dev/null || true)"; [[ -n $v ]] && sed -i "s|^base=.*|base=$v|" "$t/theme.conf"
        sddm-greeter-qt6 --test-mode --theme "$t"; rm -rf "$t" ;;
    install)
        step "Install SDDM theme → $dest"
        tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
        cp -r "$src/." "$tmp/"; cp "$shapes" "$tmp/"
        w="$(wallpaper)"
        if [[ -r $w ]]; then
            ext="${w##*.}"; rm -f "$tmp"/background.*
            cp "$w" "$tmp/background.$ext"
            sed -i "s|^background=.*|background=background.$ext|" "$tmp/theme.conf"
            ok "wallpaper: $w"
        fi
        # colours/mode from the desktop theme (dark = pitch black, light = eggshell)
        tc="${XDG_STATE_HOME:-$HOME/.local/state}/kessel/theme/colors.json"
        for k in accent mode text red; do
            v="$(jq -r --arg k "$k" '.[$k] // empty' "$tc" 2>/dev/null || true)"
            [[ -n $v ]] && sed -i "s|^$k=.*|$k=$v|" "$tmp/theme.conf"
        done
        v="$(jq -r '.bg // empty' "$tc" 2>/dev/null || true)"; [[ -n $v ]] && sed -i "s|^base=.*|base=$v|" "$tmp/theme.conf"
        info "mode: $(grep '^mode=' "$tmp/theme.conf" | cut -d= -f2)  (re-run install after switching light/dark)"
        # fingerprint login: on when /etc/pam.d/sddm uses pam_fprintd (scripts/fingerprint.sh sddm-on)
        if grep -q '^[^#]*pam_fprintd' /etc/pam.d/sddm 2>/dev/null; then
            sed -i "s|^fingerprint=.*|fingerprint=true|" "$tmp/theme.conf"; ok "fingerprint login: on"
        fi
        run sudo install -d -m 755 "$dest"
        run sudo rm -f "$dest"/background.*   # prune a stale one left by cp -r if the extension changed
        run sudo cp -r "$tmp/." "$dest/"
        run sudo chmod -R a+rX "$dest"
        if [[ -s $HOME/.face ]]; then
            run sudo install -D -m 644 "$HOME/.face" "/usr/share/sddm/faces/$USER.face.icon"
            ok "avatar: ~/.face"
        else
            info "no ~/.face — the theme shows a placeholder icon"
        fi
        # HiDPI: Hyprland scales the desktop (and the lock screen) per display, but
        # the greeter starts before Hyprland and drew at 1x, so it looked far
        # smaller than the lock. Use the laptop panel's Hyprland scale (else the
        # focused display's) for the greeter too. Override: SDDM_SCALE=1.5
        scale="${SDDM_SCALE:-}"
        if [[ -z $scale ]] && command -v hyprctl >/dev/null; then
            scale="$(hyprctl monitors -j 2>/dev/null | jq -r '(map(select(.name | test("^(eDP|LVDS|DSI)"))) + map(select(.focused)))[0].scale // empty' 2>/dev/null || true)"
        fi
        [[ $scale =~ ^[0-9]+(\.[0-9]+)?$ ]] || scale=1
        scale="$(awk -v s="$scale" 'BEGIN { printf "%g", s }')"
        general=""
        if [[ $scale != 1 ]]; then
            # PassThrough keeps fractional scales (1.5, 1.6) instead of rounding to 2
            general=$'[General]\nGreeterEnvironment=QT_SCALE_FACTOR='"$scale"$',QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough\n'
        fi
        info "greeter scale: ${scale}x (Hyprland's; override with SDDM_SCALE=…)"
        csize="$(awk -v s="$scale" 'BEGIN { printf "%d", 24 * s + 0.5 }')"
        cursor=""; [[ -d /usr/share/icons/Bibata-Modern-Classic ]] && cursor="CursorTheme=Bibata-Modern-Classic"$'\n'"CursorSize=$csize"
        if [[ -e $conf ]]; then run sudo cp -a "$conf" "$conf.kessel-bak-$ts"; info "backup: $conf.kessel-bak-$ts"; fi
        run sudo install -d -m 755 /etc/sddm.conf.d
        if (( DRY_RUN )); then
            info "[dry-run] would write $conf"
        else
            printf '# written by ~/Scripts/sddm-theme.sh — remove to restore the default theme\n%s[Theme]\nCurrent=kessel\n%s\n' "$general" "$cursor" | sudo tee "$conf" >/dev/null
        fi
        # /etc/sddm.conf can outrank /etc/sddm.conf.d/*.conf on some SDDM builds.
        # Only touch it if it already has a Current= line (e.g. a theme installed
        # outside these dots left one there) — don't create or otherwise edit the
        # file, and never touch any key besides Current=.
        if grep -q '^Current=' /etc/sddm.conf 2>/dev/null && ! grep -q '^Current=kessel$' /etc/sddm.conf; then
            run sudo cp -a /etc/sddm.conf "/etc/sddm.conf.kessel-bak-$ts"
            run sudo sed -i 's/^Current=.*/Current=kessel/' /etc/sddm.conf
            ok "/etc/sddm.conf: Current=kessel (was overriding the conf.d selection)"
        fi
        ok "selected; you'll see it at the next login screen (log out, or reboot)" ;;
    uninstall)
        step "Remove SDDM theme"
        if [[ -e $conf ]]; then run sudo mv "$conf" "$conf.kessel-bak-$ts"; ok "deselected (kept as $conf.kessel-bak-$ts)"; else info "$conf not present"; fi
        if grep -q '^Current=kessel$' /etc/sddm.conf 2>/dev/null; then
            run sudo cp -a /etc/sddm.conf "/etc/sddm.conf.kessel-bak-$ts"
            run sudo sed -i 's/^Current=kessel$/Current=/' /etc/sddm.conf
            ok "/etc/sddm.conf: cleared Current="
        fi
        run sudo rm -rf "$dest"
        ok "SDDM falls back to its default theme" ;;
    *) sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
