# SPDX-License-Identifier: GPL-3.0-or-later
# Post-install checks. Read-only. Exit status = number of failed checks.

step_check() {
    step "Post-install checks"
    local failed=0
    _c() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else fail "$1"; failed=$((failed + 1)); fi; }
    _w() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else warn "$1 (optional)"; fi; }

    _c "Hyprland config verifies (strict)" \
       "KESSEL_STRICT=1 Hyprland --verify-config -c '$HOME/.config/hypr/hyprland.lua' 2>&1 | tail -1 | grep -qx 'config ok'"
    _c "sshd is active (unchanged)"             "systemctl is-active --quiet sshd"
    _c "WayVNC not on a public address"         "! ss -ltnH | awk '{print \$4}' | grep -E ':5900\$' | grep -vqE '^(127\\.0\\.0\\.1|\\[::1\\]):5900\$'"
    _c "kitty available (terminal + fallback)"   "command -v kitty"
    _c "fuzzel available (launcher)"             "command -v fuzzel"
    _c "bash available (recovery shell)"         "command -v bash && grep -qx /usr/bin/bash /etc/shells"
    _c "fish listed in /etc/shells"              "grep -qx /usr/bin/fish /etc/shells"
    _c "JetBrainsMono Nerd Font installed"       "fc-match -f '%{family}' 'JetBrainsMono Nerd Font' | grep -q 'JetBrainsMono Nerd Font'"
    _c "no foot/rofi in the minimal profile"     "! grep -qxE '(foot|rofi|rofi-wayland)' <(read_manifest '$REPO/pkglist.txt')"
    _c "no flatpak/snap in manifests"            "! grep -qiE 'flatpak|snapd' '$REPO/pkglist.txt' '$REPO/pkglist-aur.txt'"

    local links="$REPO/profiles/$PROFILE.links" s d
    while IFS=$'\t' read -r s d; do
        [[ -e $REPO/$s ]] || continue
        _c "link ~/$d" "[[ \"\$(link_status '$REPO/$s' '$HOME/$d')\" == ok ]]"
    done < <(read_links "$links")

    if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        _c "live: no Hyprland config errors"     "[[ -z \"\$(hyprctl configerrors | tr -d '[:space:]')\" ]]"
        _c "live: SUPER+Return → kitty"          "hyprctl binds -j | jq -e '.[] | select(.modmask==64 and .key==\"Return\")'"
        _c "live: SUPER+R bound (fuzzel)"        "hyprctl binds -j | jq -e '.[] | select(.modmask==64 and .key==\"R\")'"
        _w "live: Quickshell island running"     "qs list --all 2>/dev/null | grep -q kessel"
    else
        info "not inside Hyprland — live checks skipped"
    fi
    _c "theme files generated" "[[ -s \"\${XDG_STATE_HOME:-\$HOME/.local/state}/kessel/theme/kitty.conf\" ]]"
    _w "matugen installed (wallpaper accents)" "command -v matugen"
    _w "omniglyph installed (AUR)" "command -v omniglyph"
    return $failed
}
