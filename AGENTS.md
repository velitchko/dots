# AGENTS.md: working on these dots

Guidance for AI coding agents (and humans new to the repo). Read it before changing anything. It records how the repo fits together and the pitfalls that have already cost time.

## What this repo is

Personal Arch Linux + **Hyprland (Lua config, 0.57+)** + **Quickshell** desktop (personal dotfiles; "kessel" is just the project's internal name). Everything in `~` is a **symlink into this repo**, created by `install.sh`. Editing `~/.config/...` edits the repo. License: GPL-3.0-or-later.

## Map

| Path | What lives there |
| --- | --- |
| `install.sh`, `installer/*.sh` | Idempotent installer: `common` (helpers, `run`/dry-run), `packages` (pacman/yay/laptop/translate), `config` (symlinks, backups, rollback, gsettings, theme init), `checks` |
| `profiles/minimal.links` | **Which repo paths are linked where.** Add new config here, not by hand |
| `pkglist.txt` · `pkglist-aur.txt` · `pkglist-laptop.txt` | Official · optional AUR (`--with-aur`) · laptop extras (`--with-laptop`). Every command the dots call must come from one of these |
| `.config/hypr/hyprland.lua` | Tiny loader. Modules: `monitors` `env` `general` `input` `workspaces` `exec` `keybinds` `custom` |
| `.config/hypr/keybinds.lua` | **The single keybind registry** (data only). `lib/binder.lua` turns it into binds + the `SUPER+/` list + `docs/SHORTCUTS.md` |
| `.config/hypr/lib/` | `safety.lua` (protected module loading, rescue binds), `binder.lua`, `floatmode.lua` |
| `.config/hypr/scripts/` | Shell helpers used by binds/island: `island.sh` (start/stop/restart), `island-or.sh` (island IPC with fallback), `theme.sh` (**all theming**), `lock.sh`, `translate.sh`, screenshot/clipboard/… |
| `.config/quickshell/kessel/` | The island. `shell.qml` → `ui/Island.qml`. `services/` = singletons without UI (state, D-Bus, PipeWire, processes). `ui/` = views, `ui/panels/` = expanded panels, `ui/perspectives/` = resting views. `components/` = reusable widgets. `Theme.qml`, `Icons.qml`, `Config.qml` |
| `.config/quickshell/kessel-lock/` | Separate Quickshell config for the lock screen (runs only while locked) |
| `.config/nvim/` | LazyVim. `lazyvim.json` = enabled extras; `lua/plugins/*.lua` = our additions; `lua/kessel/theme.lua` = colors from theme.sh. `lazy-lock.json` pins plugin versions (commit it after `:Lazy update`) |
| `sddm-theme/kessel/` | Qt6 SDDM theme (installed by `scripts/sddm-theme.sh`, needs sudo) |
| `scripts/` | `~/Scripts`: install/update/uninstall/backup, `gen-shortcuts.sh`, `sddm-theme.sh` |
| `services/` | **Future** systemd units. Nothing here is deployed or enabled |
| `docs/` | `DESIGN.md` (decisions + why), `SHORTCUTS.md` (generated), `THEME.md`, `backlog/` |
| `INSPIRATIONS.md` | Projects that informed the design |

## Ground rules

1. **Never `git push`.** Commit locally in small, verified steps; end commit messages with your attribution trailer if you're an agent.
2. **Never break access.** Don't touch SSH, firewall, networking, or the login shell (only `install.sh --set-shell` changes it, on request).
3. **No services.** The installer never enables system/user services. Anything in `services/` is a future, explicit opt-in.
4. **Back up before replacing.** Use the installer's link mechanism (it moves old files to `~/.local/state/dot-files/backups/<ts>/` and records a rollback manifest). Don't `cp`/`rm` over live config by hand.
5. **No secrets** in the repo, logs or output.
6. **Official repos first.** AUR only in `pkglist-aur.txt`. No Flatpak/Snap. If a package has an undeclared runtime dependency, add it to `pkglist.txt` with a comment (example: `gtk4-layer-shell` for OmniGlyph).
7. **Licensing:** respect upstream licenses. Brain_Shell is AGPL and must not be imported.
8. **Don't edit generated files.** They live in `~/.local/state/kessel/theme/`, `~/.config/{btop,yazi,qt6ct}`, `~/.config/gtk-{3,4}.0/gtk.css`, `kdeglobals`. Change `theme.sh` instead.

## How to validate (always, before committing)

```sh
KESSEL_STRICT=1 Hyprland --verify-config -c ~/.config/hypr/hyprland.lua   # must print: config ok
scripts/gen-shortcuts.sh                                                  # after any keybinds.lua change
bash -n install.sh installer/*.sh scripts/*.sh .config/hypr/scripts/*.sh
fish -n .config/fish/config.fish .config/fish/conf.d/*.fish
STARSHIP_CONFIG=.config/starship.toml starship print-config >/dev/null
./install.sh --dry-run --with-aur --apply-config                         # must change nothing
./install.sh --check
```

Island and lock (Quickshell):

```sh
~/.config/hypr/scripts/island.sh restart          # exit 1 + notification if the config fails to load
qs log -c kessel | grep -E 'WARN|ERROR|caused'    # anything new is your bug
qs -c kessel ipc show                             # all IPC entry points
KESSEL_LOCK_PREVIEW=1 qs -n -c kessel-lock -d     # lock screen WITHOUT locking; close: qs -c kessel-lock ipc call lock quit
```

**A parse succeeding is not a test.** Exercise the feature: use the IPC (`open <panel>`, `perspectiveSet`, `glance true`, `search ">de hi"`, `timer 3`) and take a screenshot (`grim -g "x,y wxh" file.png`, logical coordinates). Report anything you couldn't test (clicks, real audio, laptop hardware) explicitly.

## Pitfalls already paid for

**Hyprland (Lua)**
- Hyprland auto-reloads on save. Writing a module in several steps can be caught half-written; the safety layer then keeps rescue binds and shows a banner. Write files in one go.
- `require()` failures don't throw to `pcall`; Hyprland reports them itself. Use `KESSEL_STRICT=1 --verify-config` to surface them.
- Dispatchers validate arguments when constructed (`hl.dsp.window.move({bogus=1})` errors), so `--verify-config` catches bad binds.
- From a shell: `hyprctl dispatch 'hl.dsp.focus({ workspace = 2 })'`. A Lua function also works: `hyprctl dispatch 'function() … end'`. `hyprctl eval '…'` evaluates Lua.
- `hl.env` only affects processes started after a reload. The running session needs `hyprctl setcursor …`, a relaunch, or a re-login.

**Quickshell / QML**
- **New `.qml` files are not picked up by hot reload.** Restart: `island.sh restart`.
- **Hot reload resets state** (open panel, perspective). Don't test right after saving a file; wait about 3 s.
- **Never hard-kill a Quickshell instance with a focused text field.** Qt 6.12 crashes (`QInputMethod::commit`), and Quickshell's crash handler *restarts* the instance. Use `island.sh stop`, which calls the graceful `quit` IPC. For the lock this matters doubly: a restarted locker locks again.
- Property names Qt marks FINAL can't be redeclared (e.g. `top`). Type names must not clash with QtQuick types (`Translate` broke the whole island; the service is now `Translator`).
- `QtObject` can't host animations (use an invisible `Item`). Don't put a `MouseArea` *inside* a `Row`; wrap the Row in an `Item`.
- PipeWire node `properties` are empty until the node is tracked. Classify nodes with `PwNodeType` (`AudioOutStream`, `AudioInStream`, …).
- The island's surface is resized dynamically (small strip at rest). Blur behind a large transparent layer costs ~100% CPU without a GPU.
- Nerd Font codepoints: verify by name against the official `glyphnames.json` before using them. Guessed codepoints were wrong several times.

**Shell**
- **`pkill -f <pattern>` can match your own shell** (its command line contains the pattern). Use `pgrep -x`, PIDs, or `/proc/<pid>/cmdline` checks.
- Starting island/lock from SSH needs `HYPRLAND_INSTANCE_SIGNATURE`, `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR`. `island.sh`, `lock.sh` and `theme.sh` derive them.
- matugen ≥ 4 needs `--prefer` without a TTY. Its JSON is `.colors.<role>.<mode>.color`; its `base16` block isn't usable for terminal colors.

**Lock screen safety**
- Test with `KESSEL_LOCK_PREVIEW=1` (it never creates a session lock).
- If a real lock wedges, recover from SSH: `kill -9` the `kessel-lock` process (find it via `/proc/<pid>/cmdline`), then `hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'`. Hyprland refuses to clear while a live locker holds the lock.

## Conventions

- **Keybinds:** add entries to `keybinds.lua` only (`group`, `keys`, `desc`, `exec` or `dsp`). Duplicates are a config error. Island binds go through `island("open <panel>", "<fallback>")` so they work without Quickshell. Then run `scripts/gen-shortcuts.sh`.
- **Theme:** one pipeline: `theme.sh` → matugen roles → every consumer. Add new apps there. The base is fixed per mode (pitch black / eggshell); only accents come from the wallpaper.
- **Island features:** state/IO in a `services/*.qml` singleton, visuals in `ui/` or `components/`, an IPC function in `IslandState.qml` if it's scriptable, and a fallback for anything bound to a key.
- **Hardware-dependent UI** hides itself when the hardware or service is missing (battery, Bluetooth, backlight, power profiles).
- **Files:** SPDX header (`GPL-3.0-or-later`) on new files. Comments explain *why*.

## Where to look when something breaks

`hyprctl configerrors` · `qs log -c kessel` · `~/.cache/quickshell/crashes/` · `journalctl --user -b` · `./install.sh --check` · `docs/DESIGN.md` (why things are the way they are).
