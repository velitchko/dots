#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ~/Scripts/root-prompt.sh — the themed Starship prompt for root shells too.
#
#   root-prompt.sh install    set it up (sudo); re-run after a theme change to refresh colours
#   root-prompt.sh remove     undo it (sudo)
#   …add --dry-run to only print the commands
#
# Root doesn't read your config: `sudo -i` starts root's bash, `sudo -s` your fish
# as root, both with HOME=/root and without STARSHIP_CONFIG. So root got the
# bare default prompt. This gives root:
#   /root/.config/starship.toml              a COPY of your themed config (root shows
#                                            as a red "root" pill: style_root)
#   /root/.bashrc                            starship init, between kessel markers
#   /root/.bash_profile                      sources .bashrc (created only if missing)
#   /root/.config/fish/conf.d/kessel-prompt.fish
# A copy, never a link: a prompt config root reads must not be writable by your
# user, since Starship configs can run commands.
set -euo pipefail
repo="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
source "$repo/installer/common.sh"
for a in "$@"; do [[ $a == --dry-run ]] && DRY_RUN=1; done

marker="# copied by ~/Scripts/root-prompt.sh (re-run it after a theme change)"
begin="# >>> kessel prompt (~/Scripts/root-prompt.sh) >>>"
end="# <<< kessel prompt <<<"
themed="${XDG_STATE_HOME:-$HOME/.local/state}/kessel/theme/starship.toml"
[[ -r $themed ]] || themed="$repo/.config/starship.toml"

# remove our block from a root-owned file (prints the result to stdout)
strip_block() { sudo awk -v b="$begin" -v e="$end" '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip' "$1" 2>/dev/null || true; }

case "${1:-}" in
    install)
        command -v starship >/dev/null || die "starship is not installed"
        step "Themed prompt for root"
        tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
        { echo "$marker"; cat "$themed"; } > "$tmp/starship.toml"
        run sudo install -D -m 644 -o root -g root "$tmp/starship.toml" /root/.config/starship.toml
        ok "starship.toml ← $(basename "$(dirname "$themed")")/$(basename "$themed") (copy)"

        { strip_block /root/.bashrc
          echo "$begin"
          echo 'if [[ $- == *i* && $TERM != linux ]] && command -v starship >/dev/null; then eval "$(starship init bash)"; fi'
          echo "$end"; } > "$tmp/bashrc"
        run sudo install -m 644 -o root -g root "$tmp/bashrc" /root/.bashrc
        ok "/root/.bashrc"
        if ! sudo test -e /root/.bash_profile; then
            printf '%s\n' "$begin" '[[ -f ~/.bashrc ]] && . ~/.bashrc' "$end" > "$tmp/bash_profile"
            run sudo install -m 644 -o root -g root "$tmp/bash_profile" /root/.bash_profile
            ok "/root/.bash_profile (sources .bashrc, for sudo -i)"
        fi

        printf '%s\n' "$begin" 'if status is-interactive; and test "$TERM" != linux; and command -q starship' \
            '    starship init fish | source' 'end' "$end" > "$tmp/kessel-prompt.fish"
        run sudo install -D -m 644 -o root -g root "$tmp/kessel-prompt.fish" /root/.config/fish/conf.d/kessel-prompt.fish
        ok "/root/.config/fish/conf.d/kessel-prompt.fish (for sudo -s)"
        info "try: sudo -i   (or sudo -s)"
        ;;
    remove)
        step "Remove the root prompt"
        tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
        if sudo grep -qxF "$marker" /root/.config/starship.toml 2>/dev/null; then run sudo rm -f /root/.config/starship.toml; ok "starship.toml"; fi
        run sudo rm -f /root/.config/fish/conf.d/kessel-prompt.fish
        for f in /root/.bashrc /root/.bash_profile; do
            sudo grep -qxF "$begin" "$f" 2>/dev/null || continue
            strip_block "$f" > "$tmp/out"
            if [[ -s $tmp/out ]]; then run sudo install -m 644 -o root -g root "$tmp/out" "$f"; else run sudo rm -f "$f"; fi
            ok "$f"
        done
        ;;
    *) sed -n '3,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
