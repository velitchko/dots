# Phase 1 Quick Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix five independent, root-caused island/lock-screen bugs: an overflowing lock-screen status text, an unclickable chevron on BT/Wi-Fi/audio rows, a clipped minimal-perspective hover view, a missing Dolphin-bluetooth-share dependency, and the launcher falling back to a plain, un-themed command instead of the island's own panel whenever the island is in focus-mode (hidden).

**Architecture:** Five unrelated one-file changes (four QML, one package manifest). No shared interfaces between tasks; order doesn't matter.

**Tech Stack:** Quickshell/QML (`kessel`, `kessel-lock`), pacman package manifest.

**Spec:** `docs/superpowers/specs/2026-11-14-phase1-quick-fixes-design.md`

## Global Constraints

- SPDX header already present in every touched file; no new files.
- No new runtime dependency except Task 4's single official package (`bluez-qt`, `extra` repo).
- QML changes verified by `island.sh restart` + `qs log -c kessel` (no new WARN/ERROR) + a `grim` screenshot of the fixed element, per `AGENTS.md` ("a parse succeeding is not a test").
- Package manifest change verified by `./install.sh --dry-run --with-aur --apply-config` (must change nothing it shouldn't) before actually installing.
- Commit each task separately.

## Review Focus

- A status message much longer than "Password or fingerprint" (e.g. the actual PAM prompt text) must still fit the field, not just the two known short strings — Task 1's fix must be verified against a long string, not only the current short ones.
- The chevron fix must not swallow clicks meant for the `Switch` in rows where `showSwitch` is true (Wi-Fi/BT rows have no switch today, but the component is shared and a later row could add one) — Task 2 must verify the `Switch` still toggles independently after the change.
- The `520` width floor must not make the *minimal* perspective's resting (non-hovered) width grow — only the hover/detail view's floor changes, not the resting row.
- `bluez-qt` must not already be pulled in transitively (it isn't — confirmed via `pacman -Si bluedevil`'s dep list, which is a separate, uninstalled package) — Task 4's dry-run must show it as a genuinely new package, not a no-op. (It's since been installed manually; `pkglist.txt` still records it for fresh installs.)
- Each QML change must survive `island.sh restart` cleanly (no crash, no new `qs log` warnings) since hot-reload state resets are easy to mistake for success.
- Task 5's fix must not break the plain `toggle`/`show`/`hide` IPC functions (`IslandState.qml:124-126`) — only `open()` changes; focus-mode toggling itself (hiding the resting island when nothing is open) must still work exactly as before.

---

### Task 1: Lock-screen status text overflow

**Files:**
- Modify: `.config/quickshell/kessel-lock/LockSurface.qml:293-307` (the placeholder/status `Text`)

**Interfaces:**
- Consumes: `field` (sibling `Item`, `Layout.preferredWidth: 260`, defined at `LockSurface.qml:253-256`) — the status `Text` is a child of this `Item` and must fit within it.
- Produces: nothing consumed elsewhere; this is a leaf UI fix.

- [ ] **Step 1: Reproduce the overflow**

Run `KESSEL_LOCK_PREVIEW=1 qs -n -c kessel-lock -d` (per `AGENTS.md`), then force a long status string temporarily (e.g. edit the `fingerprintReady` branch's string to `"place right index finger on fingerprint scanner"` in a scratch copy, or trigger `fingerprintFailed` with a long `fingerprintMessage` if reachable) and take a `grim` screenshot showing the text running past the field. Close with `qs -c kessel-lock ipc call lock quit`.

- [ ] **Step 2: Bound the text to the field width**

In `LockSurface.qml`, give the status `Text` (currently unconstrained) `width: field.width` and `elide: Text.ElideRight`, keeping every existing `text:`/`color:`/`font.*` binding unchanged.

- [ ] **Step 3: Verify the fix**

Repeat Step 1's long-string reproduction under `KESSEL_LOCK_PREVIEW=1`. Expected: the text ends in an ellipsis instead of overflowing the field. Take a `grim` screenshot. Also verify the two real short strings ("Enter password", "Password or fingerprint") still render unclipped and uncentered-looking (elide on a string shorter than the field is a no-op, but confirm visually). Check `qs log -c kessel-lock` for any new WARN/ERROR before closing the preview.

- [ ] **Step 4: Commit**

```bash
git add .config/quickshell/kessel-lock/LockSurface.qml
git commit -m "lock: bound status text to the password field width"
```

---

### Task 2: BT/Wi-Fi/audio row chevron not clickable

**Files:**
- Modify: `.config/quickshell/kessel/components/SectionRow.qml:53-76` (the `tail` Row and the header `MouseArea`)

**Interfaces:**
- Consumes: `root.expandable`, `root.expanded`, `root.showSwitch`, `root.checked` (existing properties on `SectionRow`, unchanged).
- Produces: `root.toggled()`, `root.clicked()` signals — unchanged signatures, still emitted the same way, so `ControlCenter.qml`'s existing `onExpandedChanged`/`onToggled` handlers (wifi row, bt row) need no changes.

- [ ] **Step 1: Reproduce**

`island.sh restart`, then `qs -c kessel ipc call island open control`, then click directly on the chevron glyph (not elsewhere on the row) for the Wi-Fi or Bluetooth row. Expected (bug): nothing happens. Take a `grim` screenshot of the control panel for reference.

- [ ] **Step 2: Extend the hit area to cover the chevron**

In `SectionRow.qml`, change the header `MouseArea`'s `anchors.right: tail.left` so it instead spans the full header width including the chevron, while excluding the `Switch` specifically when `root.showSwitch` is true. Concretely: give the `Switch` its own small `MouseArea`-free click handling (it already has `onToggled`, which fires from pointer interaction with the `Switch` control itself, not from the row's `MouseArea`) and widen the row `MouseArea` to `anchors.right: parent.right`, since the `Switch` control consumes its own clicks and won't be shadowed by a `MouseArea` placed behind it in paint order — verify this holds in Step 3 rather than assuming it.

- [ ] **Step 3: Verify**

`island.sh restart`, reopen control center. Click the chevron directly on a Wi-Fi/BT row: it must expand/collapse. Click elsewhere on the row header: same behavior as before (expand/collapse, since these rows have no switch). If any row using `SectionRow` with `showSwitch: true` exists elsewhere in the codebase (grep for `showSwitch: true`), open that panel too and confirm the switch still toggles independently of the row's expand behavior. `qs log -c kessel` must show no new WARN/ERROR.

- [ ] **Step 4: Commit**

```bash
git add .config/quickshell/kessel/components/SectionRow.qml
git commit -m "island: fix unclickable chevron on expandable control-center rows"
```

---

### Task 3: Minimal perspective's hover/detail view clipped

**Files:**
- Modify: `.config/quickshell/kessel/ui/SummaryView.qml:11`

**Interfaces:**
- Consumes: `minWidth` (existing property, set by `Island.qml:387` to `restView.implicitWidth`) — unchanged.
- Produces: `implicitWidth` — same property, new floor value; nothing downstream reads the literal `460`.

- [ ] **Step 1: Reproduce**

`island.sh restart`, switch to the minimal perspective (`qs -c kessel ipc call island perspectiveSet minimal` — confirm the exact IPC name via `qs -c kessel ipc show` if this differs), hover the island to trigger the detail/summary view, and `grim` screenshot it next to a screenshot of an open notification (`NotificationView.qml`, width 520) for a size comparison.

- [ ] **Step 2: Raise the width floor**

In `SummaryView.qml:11`, change `implicitWidth: Math.max(460, minWidth)` to `implicitWidth: Math.max(520, minWidth)`.

- [ ] **Step 3: Verify**

Repeat Step 1. Expected: the hovered/detail view in the minimal perspective is no longer narrower than a notification and nothing is clipped. Also confirm the *resting* (non-hovered) minimal perspective row width is unchanged (it's driven by `MinimalRow.qml`'s own `implicitWidth`, not `SummaryView`, so this should be a no-op — verify by screenshot, not assumption). Check `qs log -c kessel` for any new WARN/ERROR.

- [ ] **Step 4: Commit**

```bash
git add .config/quickshell/kessel/ui/SummaryView.qml
git commit -m "island: widen minimal perspective's hover view to match notification width"
```

---

### Task 4: Dolphin "Send via Bluetooth" missing dependency

**Files:**
- Modify: `pkglist.txt`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing consumed by other tasks; installer-only change.

- [ ] **Step 1: Confirm the package name**

Already confirmed in this session: `pacman -Qo /usr/share/kf6/purpose/bluetoothplugin_config.qml` → owned by `purpose` (installed); `pacman -Si bluez-qt` → exists in `extra`, provides the `org.kde.bluezqt` QML module the error names. The user has since installed it manually (`bluez-qt installed`), so this task only needs to record it in the manifest for future installs.

- [ ] **Step 2: Add the package**

Add `bluez-qt` to `pkglist.txt`, in the Bluetooth-related section if one exists (check for an existing `bluez`/`bluez-utils` grouping and place it adjacent, matching the file's existing comment style), with a one-line comment: `# org.kde.bluezqt QML module, for Dolphin's Send via Bluetooth`.

- [ ] **Step 3: Verify**

Run `./install.sh --dry-run --with-aur --apply-config` — expected: `bluez-qt` is already satisfied (installed), and the dry-run otherwise reports no unintended changes. Confirm with the user that Dolphin's Share → Send to Bluetooth now works (it should, since the package is already installed).

- [ ] **Step 4: Commit**

```bash
git add pkglist.txt
git commit -m "pkglist: add bluez-qt for Dolphin's Send via Bluetooth"
```

---

### Task 5: Launcher inconsistent when the island is in focus mode (hidden)

**Files:**
- Modify: `.config/quickshell/kessel/services/IslandState.qml:115-118` (the `IpcHandler`'s `open(name)` function)

**Interfaces:**
- Consumes: `root.shown` (existing property, toggled by `toggle()`/`show()`/`hide()` at lines 124-126, bound to `SUPER+Space`/`SUPER+J` — unchanged by this task).
- Produces: `open(name)`'s return string, consumed by `island-or.sh`'s case match (`ok|shown|hidden\ *|...`) — after this change `open()` returns `"ok"` or `"unknown panel"`, never `"hidden"`, so no change to `island-or.sh` is needed.

- [ ] **Step 1: Reproduce**

`island.sh restart`. Run `qs -c kessel ipc call island toggle` until it reports `hidden` (focus mode on). Then run `qs -c kessel ipc call island open launcher` directly — expected (bug): prints `hidden`, and the panel does not open. Separately, trigger the real keybind (`SUPER+R`) in this hidden state and confirm bare `fuzzel` (unthemed) appears instead of the island's launcher panel.

- [ ] **Step 2: Un-hide before opening**

In `IslandState.qml`, change:
```js
function open(name: string): string {
    if (!root.shown) return "hidden"
    return root.openPanel(name) ? "ok" : "unknown panel"
}
```
to set `root.shown = true` unconditionally, then proceed to `root.openPanel(name)` as before (dropping the early `return "hidden"`).

- [ ] **Step 3: Verify**

Repeat Step 1: `qs -c kessel ipc call island toggle` into hidden state, then `qs -c kessel ipc call island open launcher` — expected: returns `ok`, the island becomes visible, and the launcher panel opens (not bare `fuzzel`). Trigger `SUPER+R` in the hidden state too and confirm the same. Then confirm `toggle`/`show`/`hide` still work unchanged: `qs -c kessel ipc call island hide` with nothing open still hides the resting island (focus mode intact when no panel is requested). `qs log -c kessel` must show no new WARN/ERROR.

- [ ] **Step 4: Commit**

```bash
git add .config/quickshell/kessel/services/IslandState.qml
git commit -m "island: open() un-hides the island instead of falling back to a bare command"
```
