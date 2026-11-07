# Design decisions

This is the reasoning behind the setup. For day-to-day use, see the [README](../README.md); for the repository map and sharp edges, see [AGENTS.md](../AGENTS.md); for color handling, see [THEME.md](THEME.md).

## Safety first

- **Quickshell is optional at runtime.** Every island binding has a fallback (fuzzel, cliphist, hyprlock, Dunst), and `lib/safety.lua` registers rescue bindings (`SUPER+Return` for kitty, `SUPER+SHIFT+Return` for plain bash) before the rest of the configuration loads.
- **Never break access.** The installer doesn't touch SSH, the firewall, networking, or the login shell (`--set-shell` only on request).
- **Bash stays the recovery shell.** fish is the interactive shell; bash is always one keybind away.
- **`SUPER+Q` closes windows, never opens a terminal**, so a reflex can't spawn shells.

## Deployment = symlinks

Each entry in `profiles/minimal.links` is a symlink from `~` into the repository. Edits land in git, and drift is visible in `git status`. If a target already exists, deployment **moves** it to a timestamped backup with a `MANIFEST`; `--rollback` and `uninstall.sh` use that manifest to restore it. Run `--dry-run` first when in doubt.

## Packages

- Official repos first (`pkglist.txt`). AUR only via `pkglist-aur.txt` and an explicit `--with-aur` (yay). No Flatpak or Snap.
- Every command the dots call comes from a package list. Undeclared runtime dependencies get a commented entry (e.g. `gtk4-layer-shell` for OmniGlyph).
- Hardware extras (`pkglist-laptop.txt`) are opt-in, and their services are never enabled automatically.

## Hyprland: modular Lua

`hyprland.lua` only loads modules, each in a protected call: `monitors` · `env` · `general` · `input` · `workspaces` · `exec` · `keybinds` · `custom`. A broken module shows a banner while the rest still applies. `keybinds.lua` is **pure data**: `lib/binder.lua` turns it into binds, the `SUPER+/` list and `docs/SHORTCUTS.md`, so the three can't disagree. Layout follows end-4/dots-hyprland for muscle memory. Every change is checked with `KESSEL_STRICT=1 Hyprland --verify-config` first.

## The island

The desktop uses one morphing surface rather than a conventional bar. It has resting perspectives (Overview, Time, Music, Metrics, Minimal) and panels that expand from it. Logic belongs in `services/` singletons; visuals belong in `ui/` and `components/`. The surface stays small at rest because a large transparent layer is costly without a GPU. The island owns notifications while it is running; Dunst activates through D-Bus when it is not, so there is one notification server at a time.

## Lock and login

The lock screen is a separate Quickshell config (`kessel-lock`) that runs only while locked, so an island crash can't take the lock down with it. `lock.sh` falls back to hyprlock if a secure lock isn't confirmed within 3 s. The SDDM theme mirrors the lock screen and is installed only by an explicit script (sudo).

## Theme

One pipeline (`theme.sh`): fixed bases (pitch black / eggshell) with accents from the wallpaper via matugen, written into every app that supports it. Generated files are not edited by hand. Details in [THEME.md](THEME.md).

## Services

`services/` is a placeholder. Nothing there is deployed or enabled by the installer. Any future unit is its own opt-in step with a reviewed unit file, a dry run and an explicit `systemctl enable`. Units that open network ports, hold credentials, or store data need a separate safety review (localhost binding, secret storage, shutdown behavior).

## Licensing

GPL-3.0-or-later. See [INSPIRATIONS.md](../INSPIRATIONS.md) for the projects that informed the design.
