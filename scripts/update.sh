#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ~/Scripts/update.sh — update the desktop.
#
#   update.sh              pull dot-files (if a remote exists), re-apply config,
#                          regenerate shortcuts, reload Hyprland, restart the island
#   update.sh --system     …and update packages: sudo pacman -Syu
#   update.sh --aur        …and AUR packages via yay, -git ones included (implies --system)
#   update.sh --dry-run    show what would happen
set -euo pipefail
repo="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
source "$repo/installer/common.sh"

SYSTEM=0 AUR=0
for a in "$@"; do
    case $a in
        --system) SYSTEM=1 ;;
        --aur) SYSTEM=1; AUR=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $a" ;;
    esac
done
(( DRY_RUN )) && printf '%sDRY RUN — nothing will be changed.%s\n' "$C_B$C_Y" "$C_0"

step "dot-files"
cd "$repo"
if [[ -n "$(git remote 2>/dev/null)" ]]; then
    if [[ -n "$(git status --porcelain)" ]]; then
        warn "local changes present — not pulling (commit or stash first)"
    else
        run git pull --ff-only
    fi
else
    info "no git remote configured — using the local repo as-is"
fi

if (( SYSTEM )); then
    step "System packages"
    run sudo pacman -Syu
    if (( AUR )); then
        command -v yay >/dev/null && run yay -Sua --devel || warn "yay not installed"   # --devel: -git packages (hyprmoncfg-git) too
    fi
fi

step "Re-apply config"
args=(--profile minimal --apply-config)
(( DRY_RUN )) && args+=(--dry-run)
"$repo/install.sh" "${args[@]}" | sed '/Post-install checks/,$d'

step "Refresh session"
run "$repo/scripts/gen-shortcuts.sh"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)"; export HYPRLAND_INSTANCE_SIGNATURE
fi
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    run hyprctl reload
    run "$HOME/.config/hypr/scripts/island.sh" restart
    run "$HOME/.config/hypr/scripts/theme.sh" apply
else
    info "Hyprland not running — session refresh skipped"
fi
(( DRY_RUN )) || "$repo/install.sh" --check || true
