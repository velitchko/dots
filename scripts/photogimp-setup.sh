#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ~/Scripts/photogimp-setup.sh — apply PhotoGIMP (Photoshop-style keymap, tool
# options, theme and splash for GIMP 3.x) from the vendored preset in
# photogimp/GIMP/3.0, so a fresh machine doesn't need the manual GIMP setup.
#
#   photogimp-setup.sh            back up the current GIMP config, apply the preset
#   photogimp-setup.sh status     show whether the preset is currently applied
#   …add --dry-run to only print what would happen
#
# Source: https://github.com/Diolinux/PhotoGIMP (GPL-3.0-or-later), native-Linux
# config only (no Flatpak desktop/icon files — this repo doesn't use Flatpak).
#
# This is a one-time seed, not a live symlink: GIMP rewrites sessionrc,
# shortcutsrc, tool-options/* etc. as you work, so symlinking the directory
# into the repo would mean every GIMP session dirties this repo. Re-run this
# script whenever you want the preset back.
#
# GIMP must have been started and closed at least once (so its config
# directory exists) and must not be running when this applies.
set -euo pipefail
repo="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
source "$repo/installer/common.sh"
src="$repo/photogimp/GIMP/3.0"

args=()
for a in "$@"; do if [[ $a == --dry-run ]]; then DRY_RUN=1; else args+=("$a"); fi; done
set -- "${args[@]+"${args[@]}"}"

gimp_config_dir() {
    command -v gimp >/dev/null 2>&1 || die "gimp not installed"
    local out
    out="$(gimp --no-interface --console-messages --batch-interpreter=plug-in-script-fu-eval \
        --batch '(begin (display "GIMP_CONFIG_DIR=") (display gimp-directory) (newline))' \
        --quit 2>&1)" || true
    sed -n 's/^GIMP_CONFIG_DIR=//p' <<<"$out" | tail -1
}

require_dir() {
    local dir; dir="$(gimp_config_dir)"
    [[ -n $dir ]] || die "couldn't detect GIMP's config directory — start GIMP once, close it, then retry"
    [[ -d $dir ]] || die "GIMP's config directory doesn't exist yet ($dir) — start GIMP once, close it, then retry"
    printf '%s' "$dir"
}

case "${1:-apply}" in
    status)
        dir="$(require_dir)"
        if [[ -f $dir/shortcutsrc ]] && diff -q "$src/shortcutsrc" "$dir/shortcutsrc" >/dev/null 2>&1; then
            ok "PhotoGIMP preset applied in $dir"
        else
            info "PhotoGIMP preset not applied in $dir"
        fi
        ;;
    apply)
        pgrep -x gimp >/dev/null 2>&1 && die "GIMP is running — close it first"
        dir="$(require_dir)"
        ts="$(date +%Y%m%d-%H%M%S)"
        bdir="$BACKUP_ROOT/$ts"
        info "backing up $dir to $bdir/GIMP"
        run mkdir -p "$bdir"
        run cp -a "$dir" "$bdir/GIMP"
        info "applying PhotoGIMP preset to $dir"
        run cp -a "$src/." "$dir/"
        ok "done — start GIMP to see it (restore: cp -a $bdir/GIMP/. $dir/)"
        ;;
    -h|--help|help)
        sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        die "unknown command '$1' (apply | status)"
        ;;
esac
