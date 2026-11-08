# Desktop details

The parts of the setup that don't fit in the README.

## Lock screen & login screen

- **Lock (`SUPER+L`)**: `kessel-lock`, a separate Quickshell config that runs only while locked. The screen "frosts over": `lock.sh` takes a screenshot of each display just before locking (raw, in your private runtime dir, deleted a few seconds later), the lock starts on it sharp and eases the blur and dark overlay in, then the blurred wallpaper (a small cached copy made by `theme.sh`) crossfades in. It has a frosted card (time, date, avatar, `$ whoami`, user), a "Locked" pill, and a bottom toolbar (keyboard layout · password · battery / sleep / shut down / restart; shut down and restart need the password). `CTRL+Enter` unlocks and keeps the session awake. Passwords are checked by PAM (`/etc/pam.d/hyprlock`); a fingerprint can unlock too (below). The avatar is `~/.face` (the SDDM copy is only a fallback). `lock.sh` falls back to **hyprlock** if the Quickshell lock can't confirm a secure lock within 3 s.
- **If a locker ever dies** (Hyprland shows "the lockscreen app died"), recover from SSH or another TTY: `hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'`, or start hyprlock (`allow_session_lock_restore` is on). Tested.
- **Login (SDDM)**: `sddm-theme/kessel` is the same design for the Qt6 greeter, with a session picker and user switching. `~/Scripts/sddm-theme.sh test` previews it in a window; `install` / `uninstall` (sudo) copy the theme, current wallpaper and `~/.face`, and select it via `/etc/sddm.conf.d/10-kessel.conf`. Re-run `install` after changing `~/.face`, the wallpaper or light/dark.

## Fingerprint

Uses `fprintd` (in `pkglist-laptop.txt`; D-Bus activated). `~/Scripts/fingerprint.sh enroll` registers a finger, `status` shows the state.

**Lock screen.** `LockContext.qml` runs two PAM conversations side by side: the password (service `hyprlock`) and a fingerprint-only stack shipped in the repo, `.config/quickshell/kessel-lock/pam/fingerprint`:

```
auth     sufficient  pam_fprintd.so max-tries=3 timeout=30
auth     required    pam_deny.so
```

Quickshell loads it through `PamContext.configDirectory`, so no system PAM file is involved. It's only started when `fprintd-list` shows an enrolled finger, and restarted after each timeout or failed match while the lock is up. Whichever succeeds first unlocks; the reader's messages ("Failed to match…") appear in the password field.

**Login screen (SDDM), opt-in.** `~/Scripts/fingerprint.sh sddm-on` inserts, before `auth include system-login` in `/etc/pam.d/sddm` (the Arch wiki setup):

```
# kessel: fingerprint login (scripts/fingerprint.sh sddm-off removes this)
auth  [success=1 new_authtok_reqd=1 default=ignore]  pam_unix.so try_first_pass likeauth nullok
auth  sufficient  pam_fprintd.so
```

A typed password passes `pam_unix` and skips the reader; an empty one falls through to `pam_fprintd`. The script shows the diff and asks, refuses a file that doesn't have the expected line, backs it up to `/etc/pam.d/sddm.kessel-bak-<ts>`, and sets `fingerprint=true` in the installed theme (which then accepts Enter on an empty field and says *Touch the fingerprint sensor…*). `sddm-off` removes exactly those lines. Recovery over SSH: `sudo cp /etc/pam.d/sddm.kessel-bak-<ts> /etc/pam.d/sddm`.

A fingerprint login can't unlock GNOME Keyring or KWallet: they're encrypted with your password.
- **Cursor**: Bibata-Modern-Classic, as in end-4 (AUR `bibata-cursor-theme-bin`, installed with `--with-aur`).
- **Theme reach**: matugen colors flow into the island, Hyprland borders, kitty (16 colors), fish, Starship, fuzzel, Qt (qt6ct, Dolphin), KDE color scheme, GTK 3/4 + libadwaita (`gtk.css`, e.g. OmniGlyph), btop, yazi, the lock screen, and SDDM (on install).

## ~/Scripts

`~/Scripts` is a symlink to this repo's `scripts/`, so you can edit it in either place. Every script supports `--dry-run`.

| Script | What it does |
| --- | --- |
| `~/Scripts/install.sh` | Fresh install / re-apply (packages + config links). Passes any `install.sh` flag through |
| `~/Scripts/update.sh` | Pull (if a remote exists) → re-apply config → regenerate shortcuts → reload Hyprland, restart island, re-apply theme. `--system` adds `pacman -Syu`, `--aur` adds `yay -Sua` |
| `~/Scripts/backup.sh` | `~/Backups/kessel/kessel-<ts>.tar.zst`: repo as a git bundle, package lists, theme/install state, notes, `~/.face`, wallpapers. Keeps 10 (`--keep N`). No secrets |
| `~/Scripts/uninstall.sh` | Undo every deployment newest-first, restoring the original files. Asks first; `--purge` also removes generated state. Never removes packages |
| `~/Scripts/sddm-theme.sh` | Login screen: `test` (window preview), `install` / `uninstall` (sudo) |
| `~/Scripts/gen-shortcuts.sh` | Rebuild `docs/SHORTCUTS.md` from `keybinds.lua` |
| `~/Scripts/fingerprint.sh` | `status`, `enroll [finger]`, `sddm-on` / `sddm-off` (sudo; fingerprint login at SDDM) |

## How config deployment works

Each entry in `profiles/minimal.links` becomes a **symlink** from `~` into this repo. Editing through `~/.config/...` therefore edits the repository, and `git status` shows the change.

- If something already exists at a link target, it is **moved** (never deleted) to `~/.local/state/dot-files/backups/<timestamp>/`, with a diff preview printed first.
- Every run that changes something writes `backups/<timestamp>/MANIFEST`, which is what `--rollback` replays.
- gsettings font and color values are recorded too, so rollback restores the previous values.

## Performance note (no GPU)

On a VM or other system without a GPU render node, `general.lua` disables blur and shadows automatically. The island also stays small when idle. This keeps software rendering sane; on the development VM it reduced Hyprland CPU use from roughly 110% to 9%. Systems with a usable GPU keep the effects.
