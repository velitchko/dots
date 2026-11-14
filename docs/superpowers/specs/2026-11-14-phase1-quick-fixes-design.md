# Phase 1: quick island/lock/launcher fixes

> Short design, agreed in conversation on 2026-11-14. First slice of a larger
> backlog triage (`issues.md`); see that conversation for the full phase
> breakdown (Phase 2 UX changes, Phase 5 multi-monitor workspaces, and
> diagnosis-only Phase 4/6 items are tracked separately, not in this doc).

## Intent

Fix four small, independent, root-caused bugs reported against the island
and lock screen. Each is a one-file change with no design ambiguity.

## Goals

- Each fix addresses the actual root cause found in the code, not just the
  symptom described in the bug report.
- No new abstractions, no refactors beyond the bug at hand.

## Non-goals / anti-goals

- Not touching the fingerprint PAM message content/length (Phase 4) — Task 1
  below only bounds the *display* of whatever message arrives, which is a
  durable UI fix independent of whether the PAM message itself is later
  shortened.

## Findings (approach for each)

1. **Lock placeholder/status text overflows.** `LockSurface.qml`'s status
   `Text` (~line 293) sits in a `field` Item sized `Layout.preferredWidth:
   260`, but the Text has no `width`/`elide` set — it renders at its natural
   width, so a long string (e.g. the PAM fingerprint prompt) overflows past
   the field instead of fitting it. The fix is structural (bound width +
   elide), not a one-off string edit, so it also protects against any other
   long status string, not just today's.
2. **BT/Wi-Fi chevron not clickable.** `SectionRow.qml`'s row `MouseArea`
   is anchored `right: tail.left`, stopping before the `tail` Row that
   contains the chevron `Glyph` — the chevron renders outside its own click
   target. Fix: extend the hit area to cover the chevron without covering
   the `Switch` (which has its own handler) when `showSwitch` is true.
3. **Minimal perspective's hover/detail view clipped.** `SummaryView.qml`
   floors its width at a hardcoded `460`; `NotificationView.qml` (the
   reference width named in the bug report) uses `520`. Fix: raise the
   floor to `520` to match.
4. **Dolphin "Send via Bluetooth" fails.** Missing QML module
   `org.kde.bluezqt`. Confirmed via `pacman -Qo` + `pacman -Si`: `purpose`
   is installed, but `bluez-qt` (which provides the QML bindings) is not.
   Fix: add `bluez-qt` to `pkglist.txt`. (Already installed manually by the
   user during this session; the plan still records it in `pkglist.txt` so
   a fresh install gets it too.)
5. **Launcher inconsistent when the island is in focus mode.** `SUPER+Space`
   /`SUPER+J` set `IslandState.qml`'s `root.shown = false` ("Focus mode:
   hide the island, frees its screen space" — a manual toggle, confirmed via
   `grep` across `keybinds.lua`; nothing auto-hides it on fullscreen).
   `IpcHandler.open(name)` then does `if (!root.shown) return "hidden"` and
   never opens the panel. `island-or.sh`'s success-match pattern
   (`hidden\ *`, which requires a trailing space) doesn't match that bare
   `"hidden"` string, so the script falls through to the plain fallback
   command (`fuzzel`, launched standalone rather than through the island) —
   this is what read as "a different/default launcher" in the original
   report. Fix: `open()` should un-hide the island and open the panel
   instead of refusing, so any panel (not just the launcher) is always
   shown consistently through the island regardless of focus-mode state.
   This also makes the `island-or.sh` fallback mismatch moot without
   touching the shell script.

## Constraints

- Follow `AGENTS.md`: SPDX header already present in touched files (no new
  files created), validate with `KESSEL_STRICT=1 Hyprland --verify-config`
  where Hyprland config is touched (not applicable here — all 4 changes are
  QML/pkglist), `island.sh restart` + a screenshot (`grim`) to exercise
  QML changes, `./install.sh --dry-run --apply-config` for the pkglist
  change.
- No new runtime dependency for Tasks 1–3. Task 4 adds exactly one official
  package (`bluez-qt`, `extra` repo — official-repos-first rule satisfied).

## What's left to the builder

Exact pixel values for width/elide in Task 1 if 260 turns out not to be the
effective constraint once rendered (verify by screenshot, not by inspection
alone).
