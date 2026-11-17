#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ~/Scripts/sddm-theme.sh — the Kessel login screen (matches the lock screen).
#
#   sddm-theme.sh test        preview in a window (no root, changes nothing)
#   sddm-theme.sh install     copy theme + current wallpaper + ~/.face, select it (sudo)
#   sddm-theme.sh sync        push the current wallpaper + colours (no sudo; theme.sh runs it)
#   sddm-theme.sh uninstall   back to SDDM's default theme (sudo)
#   …add --dry-run to install/uninstall to only print the commands
#
# System files touched (only by install/uninstall):
#   /usr/share/sddm/themes/kessel/        theme
#   /usr/share/sddm/faces/$USER.face.icon avatar (from ~/.face, if present)
#   /var/lib/kessel-sddm/                 owned by you: background + theme.conf.user, which
#                                         `sync` rewrites on every theme change (the theme's
#                                         theme.conf.user is a symlink here; SDDM reads it
#                                         over theme.conf). Login UI display: theme.conf
#                                         screen= (SDDM_SCREEN=WxH|output to override)
#   /etc/sddm.conf.d/10-kessel.conf       [Theme] Current=kessel (+ cursor), [General]
#                                         GreeterEnvironment=QT_SCALE_FACTOR=<Hyprland's scale>,
#                                         and [X11]/[Wayland] EnableHiDPI=false (the greeter's
#                                         own session starts before Hyprland and otherwise
#                                         auto-detects DPI on its own -- fractional and blurry
#                                         on this panel, same class of issue monitors.lua
#                                         documents and avoids for Hyprland's own compositing)
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
live=/var/lib/kessel-sddm   # user-writable, so the wallpaper/colours follow theme.sh without sudo
tc="${XDG_STATE_HOME:-$HOME/.local/state}/kessel/theme/colors.json"
ts="$(date +%Y%m%d-%H%M%S)"

cmd=${1:-}; shift || true
[[ ${1:-} == --dry-run ]] && DRY_RUN=1

wallpaper() { jq -r '.wallpaper // empty' "${XDG_STATE_HOME:-$HOME/.local/state}/kessel/theme/colors.json" 2>/dev/null || true; }
accent()    { jq -r '.accent // "#8aadf4"' "${XDG_STATE_HOME:-$HOME/.local/state}/kessel/theme/colors.json" 2>/dev/null || echo "#8aadf4"; }

# sync: write the live background + theme.conf.user (SDDM can't read your home)
sync_live() {
    [[ -w $live ]] || { info "$live not set up: run sddm-theme.sh install once"; return 0; }
    local w ext k v size base mode pre=false
    w="$(wallpaper)"
    {
        echo "# written by ~/Scripts/sddm-theme.sh sync — overrides theme.conf"
        echo "[General]"
        if [[ -r $w ]]; then
            # Pre-render blur + darkening at 16 bits and dither down to 8: the
            # greeter's own MultiEffect blur under a 62% overlay leaves too few
            # shades in a dark wallpaper and shows hard contour bands.
            if command -v magick >/dev/null; then
                size="$(hyprctl monitors -j 2>/dev/null | jq -r 'max_by(.width * .height) | "\(.width)x\(.height)"' 2>/dev/null || true)"
                [[ $size =~ ^[0-9]+x[0-9]+$ ]] || size=2560x1440
                base="$(jq -r '.bg // "#000000"' "$tc" 2>/dev/null || echo "#000000")"
                mode="$(jq -r '.mode // "dark"' "$tc" 2>/dev/null || echo dark)"
                if nice magick "$w[0]" -resize "$size^" -gravity center -extent "$size" -depth 16 \
                        -modulate 100,90 -blur 0x32 -fill "$base" -colorize "$([[ $mode == light ]] && echo 58 || echo 62)" \
                        -attenuate 0.6 +noise Uniform -depth 8 "png:$live/.bg.tmp" 2>/dev/null; then
                    w="$live/.bg.tmp"; ext=png; pre=true
                fi
            fi
            if [[ $pre == false ]]; then
                ext="${w##*.}"; cp "$w" "$live/.bg.tmp"
            fi
            mv -f "$live/.bg.tmp" "$live/background.$ext"
            find "$live" -maxdepth 1 -name 'background.*' ! -name "background.$ext" -delete
            echo "background=$live/background.$ext"
            echo "prerendered=$pre"
        fi
        for k in accent mode text red; do
            v="$(jq -r --arg k "$k" '.[$k] // empty' "$tc" 2>/dev/null || true)"; [[ -n $v ]] && echo "$k=$v"
        done
        v="$(jq -r '.bg // empty' "$tc" 2>/dev/null || true)"; [[ -n $v ]] && echo "base=$v"
    } > "$live/.conf.tmp" && mv -f "$live/.conf.tmp" "$live/theme.conf.user"
    chmod a+r "$live"/* 2>/dev/null || true
}

if [[ $cmd == sync ]]; then sync_live; exit 0; fi

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
        # login UI on one display only: SDDM_SCREEN, else the largest one (if several)
        scr="${SDDM_SCREEN:-}"
        if [[ -z $scr ]] && command -v hyprctl >/dev/null; then
            scr="$(hyprctl monitors -j 2>/dev/null | jq -r 'if length > 1 then max_by(.width * .height) | "\(.width)x\(.height)" else empty end' 2>/dev/null || true)"
        fi
        sed -i "s|^screen=.*|screen=$scr|" "$tmp/theme.conf"
        info "login UI on: ${scr:-SDDM's primary display} (others show the wallpaper; override: SDDM_SCREEN=WxH)"
        # fingerprint login: on when /etc/pam.d/sddm uses pam_fprintd (scripts/fingerprint.sh sddm-on)
        if grep -q '^[^#]*pam_fprintd' /etc/pam.d/sddm 2>/dev/null; then
            sed -i "s|^fingerprint=.*|fingerprint=true|" "$tmp/theme.conf"; ok "fingerprint login: on"
        fi
        run sudo install -d -m 755 "$dest"
        run sudo rm -f "$dest"/background.*   # prune a stale one left by cp -r if the extension changed
        run sudo cp -r "$tmp/." "$dest/"
        # live wallpaper/colours: theme.sh keeps $live current from now on
        run sudo install -d -m 755 -o "$USER" -g "$(id -gn)" "$live"
        run sudo ln -sfn "$live/theme.conf.user" "$dest/theme.conf.user"
        run sudo chmod -R a+rX "$dest"
        (( DRY_RUN )) || sync_live
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
        # Always pin an explicit scale, even at 1x (previously skipped as "no
        # override needed" when scale==1) -- SDDM's own greeter session starts
        # before Hyprland, in its own X11 (or Wayland) session with no idea
        # monitors.lua pinned this panel to scale=1. Left alone, SDDM/Qt's
        # own HiDPI auto-detection (X11's EnableHiDPI=true default) reads the
        # panel's physical DPI directly -- 168 DPI here, which rounds to a
        # *fractional* ~1.75x -- and fractional scale renders visibly soft on
        # this same Qt6 stack, the exact reason monitors.lua avoids it for
        # Hyprland's own compositing too. EnableHiDPI=false turns that
        # auto-detection off in both backends so QT_SCALE_FACTOR is the only
        # scale actually in effect. (PassThrough keeps a fractional
        # SDDM_SCALE override, e.g. 1.5, instead of rounding it to 2.)
        general=$'[General]\nGreeterEnvironment=QT_SCALE_FACTOR='"$scale"$',QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough\n[X11]\nEnableHiDPI=false\n[Wayland]\nEnableHiDPI=false\n'
        info "greeter scale: ${scale}x, HiDPI auto-detection off (Hyprland's scale; override with SDDM_SCALE=…)"
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
        run sudo rm -rf "$dest" "$live"
        ok "SDDM falls back to its default theme" ;;
    *) sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
