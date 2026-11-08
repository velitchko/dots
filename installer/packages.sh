# SPDX-License-Identifier: GPL-3.0-or-later
# Package steps: official repos (pacman) and optional AUR (yay, opt-in only).

# missing_pkgs MANIFEST — packages from MANIFEST not currently installed.
missing_pkgs() {
    local p
    while read -r p; do
        # foo-bin is also satisfied by foo (the same program built from source,
        # e.g. when a -bin download is temporarily failing)
        pacman -Qq "$p" >/dev/null 2>&1 || pacman -Qqg "$p" >/dev/null 2>&1 ||
            { [[ $p == *-bin ]] && pacman -Qq "${p%-bin}" >/dev/null 2>&1; } || echo "$p"
    done < <(read_manifest "$1")
}

step_packages() {
    local manifest="$REPO/pkglist.txt"
    step "Official packages ($(read_manifest "$manifest" | wc -l) in pkglist.txt)"
    local missing p
    mapfile -t missing < <(missing_pkgs "$manifest")
    if (( ${#missing[@]} == 0 )); then
        ok "all installed"
        return
    fi
    for p in "${missing[@]}"; do
        pacman -Si "$p" >/dev/null 2>&1 || die "'$p' is not in the configured repositories"
    done
    info "missing: ${missing[*]}"
    run sudo pacman -S --needed "${missing[@]}"
}

# Install yay (AUR helper) from the AUR's prebuilt yay-bin, once.
bootstrap_yay() {
    info "yay not found — bootstrapping yay-bin from the AUR"
    local missing; mapfile -t missing < <(for p in git base-devel; do pacman -Qq "$p" >/dev/null 2>&1 || pacman -Qqg "$p" >/dev/null 2>&1 || echo "$p"; done)
    (( ${#missing[@]} )) && run sudo pacman -S --needed "${missing[@]}"
    local tmp; tmp="$(mktemp -d)"
    run git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    if (( DRY_RUN )); then info "[dry-run] (cd $tmp/yay-bin && makepkg -si)"; rm -rf "$tmp"; return 0; fi
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm) || { rm -rf "$tmp"; warn "yay bootstrap failed"; return 1; }
    rm -rf "$tmp"
    ok "yay installed"
}

step_aur() {
    local manifest="$REPO/pkglist-aur.txt"
    step "Optional AUR packages (--with-aur)"
    local missing
    mapfile -t missing < <(missing_pkgs "$manifest")
    if (( ${#missing[@]} == 0 )); then
        ok "all installed"
        return
    fi
    info "missing: ${missing[*]}"
    if ! command -v yay >/dev/null 2>&1; then
        bootstrap_yay || return 1
    fi
    run yay -S --needed "${missing[@]}"
}

step_translate() {
    step "Offline translation (--with-translate)"
    local t="$REPO/.config/hypr/scripts/translate.sh"
    info "private Python 3.10 + bergamot (via uv) and models: en↔de, en↔bg (de↔bg pivots via en)"
    info "more languages later: ~/.config/hypr/scripts/translate.sh available | add <pair>"
    run "$t" setup en-de de-en en-bg bg-en
}

step_tex() {
    local manifest="$REPO/pkglist-tex.txt"
    step "LaTeX toolchain (--with-tex)"
    local missing
    mapfile -t missing < <(missing_pkgs "$manifest")
    if (( ${#missing[@]} == 0 )); then ok "all installed"; else
        info "missing: ${missing[*]}"
        run sudo pacman -S --needed "${missing[@]}"
    fi
}

step_laptop() {
    local manifest="$REPO/pkglist-laptop.txt"
    step "Laptop extras (--with-laptop)"
    local missing
    mapfile -t missing < <(missing_pkgs "$manifest")
    if (( ${#missing[@]} == 0 )); then ok "all installed"; else
        info "missing: ${missing[*]}"
        run sudo pacman -S --needed "${missing[@]}"
    fi
    info "services are NOT enabled by the installer; if wanted:"
    info "  sudo systemctl enable --now bluetooth.service power-profiles-daemon.service"
}
