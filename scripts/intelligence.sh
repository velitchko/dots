#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ~/Scripts/intelligence.sh — local models (Ollama) for the AI chat (SUPER+I).
#
#   intelligence.sh status           package, service, API, pulled models, chat's model
#   intelligence.sh setup [model]    install + start Ollama, pull a model (default qwen2.5:3b), point the chat at it (sudo)
#   intelligence.sh pull <model>     pull another model and make it the chat's Ollama model
#   …add --dry-run to setup / pull to only show what would happen
#
# Why a script and not install.sh: ollama ships a system service, and the
# installer never enables services (AGENTS.md rule 3). Running this is the
# explicit opt-in, once per machine.
#
# GPU: an NVIDIA card gets ollama-cuda as well (Ollama loads it on its own);
# everything else runs on the CPU, which is fine for 3B models. Override the
# extra package with OLLAMA_GPU_PKG=ollama-rocm (or "" for none).
#
# The chat's settings (~/.local/state/kessel/ai/settings.json) are only filled
# in, never overridden: an Ollama model you already picked stays, and so does
# a different provider. `pull` sets the Ollama model explicitly.
set -euo pipefail
repo="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
source "$repo/installer/common.sh"

api="http://localhost:11434"
default_model="qwen2.5:3b"
settings="$HOME/.local/state/kessel/ai/settings.json"

args=()
for a in "$@"; do if [[ $a == --dry-run ]]; then DRY_RUN=1; else args+=("$a"); fi; done
set -- "${args[@]+"${args[@]}"}"

api_up() { curl -fsS --max-time 2 "$api/api/version" >/dev/null 2>&1; }
chat_model() { jq -r '.providerModels.ollama // empty' "$settings" 2>/dev/null || true; }

gpu_pkg() {
    if [[ -n ${OLLAMA_GPU_PKG+x} ]]; then printf '%s' "$OLLAMA_GPU_PKG"; return; fi
    # Not `lspci | grep -q`: with pipefail, grep -q quitting early SIGPIPEs lspci and the match reads as a failure.
    local pci; pci="$(lspci 2>/dev/null || true)"
    if grep -Eqi '(vga|3d).*nvidia' <<<"$pci"; then printf 'ollama-cuda'; fi
}

install_pkgs() {
    local want=(ollama) missing=() g
    g="$(gpu_pkg)"; [[ -n $g ]] && want+=("$g")
    for p in "${want[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
    if (( ${#missing[@]} )); then run sudo pacman -S --needed "${missing[@]}"
    else ok "installed: ${want[*]}"; fi
}

start_service() {
    if systemctl is-enabled ollama.service >/dev/null 2>&1 && systemctl is-active ollama.service >/dev/null 2>&1; then
        ok "ollama.service enabled and running"
    else
        run sudo systemctl enable --now ollama.service
    fi
    (( DRY_RUN )) && return 0
    for _ in $(seq 30); do api_up && { ok "API answering on $api"; return 0; }; sleep 0.5; done
    die "ollama.service started but $api doesn't answer: journalctl -u ollama -b"
}

pull_model() {
    if ollama list 2>/dev/null | awk 'NR > 1 { print $1 }' | grep -qxF "$1"; then ok "model $1 already pulled"
    else run ollama pull "$1"; fi
}

# set_chat_model MODEL force — fill providerModels.ollama (force=1 overrides an existing one).
set_chat_model() {
    local cur; cur="$(chat_model)"
    if [[ $cur == "$1" ]]; then ok "AI chat already uses $1"; return 0; fi
    if [[ -n $cur && $2 == 0 ]]; then info "AI chat keeps its Ollama model $cur (intelligence.sh pull $1 to switch)"; return 0; fi
    if (( DRY_RUN )); then info "[dry-run] set AI chat's Ollama model to $1 in $settings"; return 0; fi
    mkdir -p "$(dirname "$settings")"
    local tmp; tmp="$(mktemp)"
    { cat "$settings" 2>/dev/null || echo '{}'; } \
        | jq --arg m "$1" '(if type == "object" then . else {} end)
                           | .provider //= "ollama" | .providerModels = ((.providerModels // {}) + {ollama: $m})' > "$tmp"
    mv "$tmp" "$settings"
    ok "AI chat's Ollama model: $1"
    # The island reads settings.json only at startup (and would write its old
    # values back on the next change), so reload it if it's running.
    if pgrep -x qs >/dev/null || pgrep -x quickshell >/dev/null; then
        "$repo/scripts/desktop/island.sh" restart >/dev/null 2>&1 && info "island restarted to pick it up" \
            || warn "restart the island to pick it up: ~/.config/hypr/scripts/island.sh restart"
    fi
}

case "${1:-status}" in
    status)
        if pacman -Qq ollama >/dev/null 2>&1; then ok "ollama installed ($(pacman -Q ollama | cut -d' ' -f2))"
        else warn "ollama not installed: intelligence.sh setup"; exit 0; fi
        g="$(gpu_pkg)"
        if [[ -n $g ]]; then
            if pacman -Qq "$g" >/dev/null 2>&1; then ok "$g installed"; else warn "$g missing (GPU detected): intelligence.sh setup"; fi
        else info "no GPU backend (CPU inference)"; fi
        if systemctl is-active ollama.service >/dev/null 2>&1; then ok "ollama.service running"
        else warn "ollama.service not running: intelligence.sh setup"; fi
        if api_up; then
            ok "API answering on $api"
            models="$(ollama list 2>/dev/null | awk 'NR > 1 { print $1 }' | tr '\n' ' ')"
            if [[ -n $models ]]; then ok "models: $models"; else warn "no models pulled: intelligence.sh pull $default_model"; fi
        fi
        m="$(chat_model)"
        if [[ -n $m ]]; then ok "AI chat's Ollama model: $m"; else info "AI chat has no Ollama model set"; fi
        ;;
    setup)
        model="${2:-$default_model}"
        step "Ollama"
        install_pkgs
        start_service
        step "Model $model"
        pull_model "$model"
        set_chat_model "$model" 0
        ;;
    pull)
        [[ -n ${2:-} ]] || die "usage: intelligence.sh pull <model>   (e.g. qwen2.5:7b, llama3.2:3b)"
        api_up || (( DRY_RUN )) || die "Ollama isn't running: intelligence.sh setup"
        pull_model "$2"
        set_chat_model "$2" 1
        ;;
    -h|--help|help)
        sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        die "unknown command '$1' (status | setup [model] | pull <model>)"
        ;;
esac
