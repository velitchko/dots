# Contributing

These are personal dotfiles, but focused bug reports and pull requests are welcome. If you are an AI agent, start with [`AGENTS.md`](AGENTS.md).

## Reporting a bug

Use the **Bug report** template. The aim is to make the problem reproducible without a round of guesswork. Include:

1. **What happened vs. what you expected.** One or two sentences.
2. **Steps to reproduce.** Keys pressed, panel opened, what you clicked.
3. **Your setup**:
   ```sh
   hyprctl version | head -1
   qs --version
   uname -r
   hyprctl monitors | grep -E 'Monitor|scale'
   ```
   Also say whether it's a laptop, desktop, or VM, and whether you use a GPU or multiple monitors.
4. **Diagnostics** (paste the relevant part, not everything):
   ```sh
   ./install.sh --check
   hyprctl configerrors
   qs log -c kessel | grep -E 'WARN|ERROR|caused' | tail -30
   ls ~/.cache/quickshell/crashes/      # if Quickshell crashed: attach report.txt
   ```
5. **A screenshot or short recording** if it's visual (`SUPER+SHIFT+S` / `SUPER+SHIFT+R`).

**Before posting**, remove anything private from logs: usernames you'd rather not share, hostnames, IP addresses, Wi‑Fi names, tokens. Never post passwords or keys.

**Security problems** (e.g. something that could unlock the lock screen or expose a port) shouldn't go in a public issue. Contact the maintainer privately first.

Feature requests are welcome too. Explain the problem first, not only the feature you have in mind.

## Making a pull request

1. **Fork and branch** from `main` (`fix/short-name` or `feat/short-name`). Keep one topic per PR.
2. **Follow the structure** described in `AGENTS.md`:
   - New config is linked via `profiles/minimal.links`, not copied by hand.
   - New dependencies go into `pkglist.txt` (official), `pkglist-aur.txt` (optional AUR) or `pkglist-laptop.txt`, with a comment saying why.
   - Keybinds only in `.config/hypr/keybinds.lua`, then `scripts/gen-shortcuts.sh`.
   - Colors only through `scripts/theme.sh` / `Theme.qml`. No hard-coded colors in components.
   - Island features: logic in `services/`, visuals in `ui/` or `components/`, and a Quickshell-independent fallback for anything on a key.
3. **Don't**: enable services, change SSH/network/firewall settings, add Flatpak/Snap, or commit secrets. Respect upstream licenses when using external references.
4. **Validate** (all must pass):
   ```sh
   KESSEL_STRICT=1 Hyprland --verify-config -c ~/.config/hypr/hyprland.lua
   bash -n install.sh installer/*.sh scripts/*.sh .config/hypr/scripts/*.sh
   ./install.sh --dry-run --with-aur --apply-config
   ~/.config/hypr/scripts/island.sh restart && qs log -c kessel | grep -E 'ERROR|caused'
   ```
5. **Test it in a real Hyprland session.** State what you tested and what you could not—for example, “no laptop available to test the battery panel.”
6. **Commits:** short imperative subject with an area prefix (`island: …`, `hypr: …`, `theme: …`, `installer: …`, `docs: …`). Explain *why* in the body. If an AI agent wrote the change, keep its `Co-Authored-By` trailer.
7. **Docs:** update `README.md` / `docs/` when behavior or keys change.

The PR template has a checklist for all of this.

## License

By contributing you agree your contribution is licensed under **GPL-3.0-or-later**, the license of this repository. New files start with `// SPDX-License-Identifier: GPL-3.0-or-later` (or `#` for shell/Lua/TOML).
