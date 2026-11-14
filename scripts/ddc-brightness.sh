#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ddc-brightness.sh — one-time setup so the island's brightness slider can also
# reach external monitors over DDC/CI (ddcutil), not just the laptop panel.
#
#   ddc-brightness.sh test                   list DDC-capable displays (no root)
#   ddc-brightness.sh install [--dry-run]    udev rule + i2c group (sudo)
#   ddc-brightness.sh uninstall [--dry-run]  remove the udev rule (sudo)
#
# System files touched (only by install/uninstall):
#   /etc/udev/rules.d/45-ddcutil-i2c.rules   KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
#                                             (/dev/i2c-* is root-only by default; this lets
#                                             the i2c group read/write it without sudo)
# Existing files are backed up to *.kessel-bak-<ts> first.
# Without this, external monitors are skipped silently -- Brightness.qml only
# controls the laptop panel, same as before this script exists.
# Recovery: sudo rm /etc/udev/rules.d/45-ddcutil-i2c.rules && sudo udevadm control --reload-rules
set -euo pipefail
repo="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
source "$repo/installer/common.sh"
rule=/etc/udev/rules.d/45-ddcutil-i2c.rules
ts="$(date +%Y%m%d-%H%M%S)"

cmd=${1:-}; shift || true
[[ ${1:-} == --dry-run ]] && DRY_RUN=1

need_ddcutil() { command -v ddcutil >/dev/null || die "ddcutil is not installed: sudo pacman -S ddcutil"; }

case $cmd in
    test)
        need_ddcutil
        ddcutil detect ;;
    install)
        need_ddcutil
        step "Udev rule: i2c group gets read/write on /dev/i2c-*"
        tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
        cat > "$tmp" <<'RULE'
# Installed by dot-files/scripts/ddc-brightness.sh -- lets ddcutil talk to
# external monitors over I2C without running as root.
KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
RULE
        [[ -e $rule ]] && { run sudo cp -p "$rule" "$rule.kessel-bak-$ts"; info "backup: $rule.kessel-bak-$ts"; }
        run sudo install -m 644 "$tmp" "$rule"
        run sudo udevadm control --reload-rules
        run sudo udevadm trigger
        ok "$rule"
        if id -nG "$USER" | grep -qw i2c; then
            ok "$USER is already in the i2c group"
        else
            run sudo usermod -aG i2c "$USER"
            warn "added $USER to the i2c group -- log out and back in for it to take effect"
        fi
        step "Detected displays"
        ddcutil detect || true ;;
    uninstall)
        step "Remove udev rule"
        if [[ -e $rule ]]; then
            run sudo rm "$rule"
            ok "removed $rule"
        else
            info "nothing to remove"
        fi
        run sudo udevadm control --reload-rules
        run sudo udevadm trigger ;;
    *)
        echo "usage: $0 test|install|uninstall [--dry-run]" >&2
        exit 2 ;;
esac
