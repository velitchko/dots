#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ~/Scripts/fingerprint.sh — fingerprint reader for the lock and login screens.
#
#   fingerprint.sh status            reader, enrolled fingers, SDDM login state
#   fingerprint.sh enroll [finger]   enroll a finger (default right-index-finger)
#   fingerprint.sh sddm-on           allow fingerprint login at SDDM (sudo)
#   fingerprint.sh sddm-off          undo sddm-on (sudo)
#   …add --dry-run to sddm-on / sddm-off to only show what would change
#
# The LOCK SCREEN needs none of this beyond `enroll`: it ships its own
# fingerprint PAM stack (kessel-lock/pam/fingerprint) and offers it next to
# the password as soon as a finger is enrolled.
#
# SDDM uses /etc/pam.d/sddm. sddm-on adds two lines before `auth include
# system-login` (the Arch wiki setup): a typed password is checked as usual;
# an EMPTY password (just Enter) goes to the fingerprint reader. Logging in by
# fingerprint can't unlock a keyring (GNOME Keyring / KWallet need the password).
# The original file is backed up to /etc/pam.d/sddm.kessel-bak-<ts>. Recovery,
# e.g. over SSH:  sudo cp /etc/pam.d/sddm.kessel-bak-<ts> /etc/pam.d/sddm
set -euo pipefail
repo="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
source "$repo/installer/common.sh"

pam=/etc/pam.d/sddm
theme=/usr/share/sddm/themes/kessel/theme.conf
marker="# kessel: fingerprint login (scripts/fingerprint.sh sddm-off removes this)"
ts="$(date +%Y%m%d-%H%M%S)"

for a in "$@"; do [[ $a == --dry-run ]] && DRY_RUN=1; done

need_fprintd() {
    command -v fprintd-list >/dev/null || die "fprintd is not installed: ./install.sh --with-laptop (or sudo pacman -S fprintd)"
}
enrolled() { fprintd-list "$USER" 2>/dev/null | grep -qi "finger"; }
sddm_on() { grep -q '^[^#]*pam_fprintd' "$pam" 2>/dev/null; }

set_theme_flag() {   # the installed SDDM theme shows "Enter + fingerprint" when true
    [[ -f $theme ]] || return 0
    run sudo sed -i "s|^fingerprint=.*|fingerprint=$1|" "$theme"
    grep -q '^fingerprint=' "$theme" || run sudo sh -c "printf 'fingerprint=%s\n' '$1' >> '$theme'"
}

case "${1:-status}" in
    status)
        if command -v fprintd-list >/dev/null; then ok "fprintd installed"; else warn "fprintd not installed (./install.sh --with-laptop)"; exit 0; fi
        if enrolled; then ok "enrolled: $(fprintd-list "$USER" 2>/dev/null | grep -oE '[a-z]+-[a-z]+(-[a-z]+)?-finger' | sort -u | tr '\n' ' ')"
        else warn "no finger enrolled: fingerprint.sh enroll"; fi
        if sddm_on; then ok "SDDM fingerprint login: on"; else info "SDDM fingerprint login: off (fingerprint.sh sddm-on)"; fi
        ;;
    enroll)
        need_fprintd
        finger="${2:-right-index-finger}"
        step "Enroll $finger (touch the sensor repeatedly until it says done)"
        fprintd-enroll -f "$finger" "$USER"
        fprintd-verify "$USER" || warn "verification failed: try enrolling again"
        ;;
    sddm-on)
        need_fprintd
        enrolled || die "enroll a finger first: fingerprint.sh enroll"
        [[ -f $pam ]] || die "$pam not found (is SDDM installed?)"
        if sddm_on; then ok "already on"; set_theme_flag true; exit 0; fi
        grep -q '^auth[[:space:]]\+include[[:space:]]\+system-login' "$pam" \
            || die "$pam doesn't have the expected 'auth include system-login' line; not touching it"
        step "Fingerprint login at SDDM"
        tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
        awk -v m="$marker" '
            !done && /^auth[ \t]+include[ \t]+system-login/ {
                print m
                print "auth        [success=1 new_authtok_reqd=1 default=ignore]  pam_unix.so try_first_pass likeauth nullok"
                print "auth        sufficient  pam_fprintd.so"
                done = 1
            }
            { print }' "$pam" > "$tmp"
        diff -u "$pam" "$tmp" || true
        if (( ! DRY_RUN )); then
            read -r -p "  Apply this to $pam? [y/N] " yn
            [[ $yn == [yY]* ]] || die "nothing changed"
        fi
        run sudo cp -p "$pam" "$pam.kessel-bak-$ts"
        run sudo install -m 644 "$tmp" "$pam"
        set_theme_flag true
        ok "on. At the login screen: press Enter on an empty password, then touch the sensor"
        info "backup: $pam.kessel-bak-$ts"
        ;;
    sddm-off)
        [[ -f $pam ]] || die "$pam not found"
        sddm_on || { ok "already off"; set_theme_flag false; exit 0; }
        step "Remove fingerprint login from SDDM"
        tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
        awk -v m="$marker" '
            $0 == m { skip = 2; next }
            skip > 0 && (/pam_unix\.so try_first_pass likeauth/ || /pam_fprintd\.so/) { skip--; next }
            { print }' "$pam" > "$tmp"
        diff -u "$pam" "$tmp" || true
        run sudo cp -p "$pam" "$pam.kessel-bak-$ts"
        run sudo install -m 644 "$tmp" "$pam"
        set_theme_flag false
        ok "off (backup: $pam.kessel-bak-$ts)"
        ;;
    *) sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
