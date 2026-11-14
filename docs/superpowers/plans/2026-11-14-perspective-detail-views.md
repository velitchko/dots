# Perspective Detail Views Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the island's hover view (`SummaryView.qml`) show perspective-specific content — richer now-playing on Music, a timezone row + 7-day forecast on Time, bigger charts + top-5 process lists on Metrics — while every perspective keeps the same baseline (time/user/date/weather/now-playing/brief metrics) and the view's width stays fixed at 520px.

**Architecture:** `SummaryView.qml` gains three `readonly property bool` perspective flags (`isMusic`, `isTime`, `isSystem`) read from `Perspectives.current`. The existing `MediaCard` instance's `compact` binding becomes perspective-aware; two new `visible`-gated `Column`s (Time's, Metrics') are added below the existing chips row. Two new singleton services (`Timezones.qml`, `Processes.qml`) provide the new data, each gated by a `wanted` property so their `Process`-based polling only runs while their section is actually visible — mirrors `Cava.wanted`'s existing gating pattern in this codebase.

**Tech Stack:** QML (Quickshell), bash (`date` with `TZ=`, `ps`).

**Spec:** `docs/superpowers/specs/2026-11-14-perspective-detail-views-design.md`

## Global Constraints

- `SummaryView.implicitWidth` stays `520` (unchanged) — new content must fit within that width via vertical stacking / compact rows, never by widening the view.
- No new runtime dependency (`date` and `ps` are already present via `procps-ng`, already a base-system dependency on Arch).
- Every new `Process`-based poller is gated by a `wanted: bool` property and must not run while its section isn't visible (`View.shown` + the relevant perspective flag).
- SPDX header on every new file.

## Review Focus

- Switching perspectives *while hovering* (scroll wheel rotates `Perspectives.current` without necessarily closing the hover glance) must correctly swap which extra section is visible and stop/start the right pollers — not leave a stale section visible or a poller running after its section is hidden.
- A `ps` line whose process name happens to be empty or whose output doesn't match the expected `name` + whitespace + `number` shape (e.g. a transient process that exited between listing and parsing) must not crash the parse or inject a broken row — skip it.
- `Weather.forecast` can have fewer than 7 entries (API hiccup, just-started), and `Media.album` can be empty (many tracks/players don't set it) — both must degrade to "show what's there," not an empty/broken-looking row.
- The two new services' `Process` calls must actually stop running when `wanted` becomes `false` (not just stop being *read* in the UI) — confirm via the live process list, not just the QML binding.
- Hovering a perspective that has no extra section (Overview, Minimal) after having hovered one that does (Time, Metrics) must not leave the old section's height/space behind.

---

### Task 1: Music's richer now-playing slot

**Files:**
- Modify: `.config/quickshell/kessel/components/MediaCard.qml:51` (the artist `Label`)
- Modify: `.config/quickshell/kessel/ui/SummaryView.qml` (the `MediaCard` instantiation, plus the new `isMusic` flag)

**Interfaces:**
- Consumes: `Media.album` (existing property, `services/Media.qml:20`, currently unread anywhere), `Perspectives.current` (existing property, `services/Perspectives.qml:17`).
- Produces: nothing new consumed elsewhere.

- [ ] **Step 1: Reproduce the current (lack of) behavior**

`island.sh restart`, then with something playing: `qs -c kessel ipc call island perspectiveSet music`, `qs -c kessel ipc call island glance true`, `grim` a screenshot. Expected: the now-playing card shows title and artist only, no album, at the compact (92px-tall) size regardless of perspective.

- [ ] **Step 2: Show the album alongside the artist**

In `MediaCard.qml`, change the artist `Label`'s `text:` binding from `Media.artist || Media.identity` to also append the album when present: `(Media.artist || Media.identity) + (Media.album ? " · " + Media.album : "")`. No height/layout change — this is the same `Label`, just a longer string (already handled by the existing `width: parent.width` binding; it elides/wraps however that `Label` already does today for a long artist name).

- [ ] **Step 3: Add the `isMusic` flag and make the card non-compact on Music**

In `SummaryView.qml`, add `readonly property bool isMusic: Perspectives.current === "music"` near the top of the `View`. Change the `MediaCard`'s `compact: true` to `compact: !root.isMusic`.

- [ ] **Step 4: Verify**

Repeat Step 1's reproduction. Expected: on the Music perspective, the card is now 104px tall (not 92) and the artist line reads "Artist · Album" (or just "Artist" if the player doesn't report an album — confirm by checking `Media.album` for the currently-playing track first, e.g. via a quick `console.log` or by checking what the real player reports). On every *other* perspective with something playing (e.g. Overview), confirm the card is still compact (92px) and shows the same "Artist · Album" text (the text change applies everywhere, only the height differs by perspective). `qs log -c kessel` must show no new WARN/ERROR.

- [ ] **Step 5: Commit**

```bash
git add .config/quickshell/kessel/components/MediaCard.qml .config/quickshell/kessel/ui/SummaryView.qml
git commit -m "island: richer now-playing card on the Music perspective's hover view"
```

---

### Task 2: Time's extra section (timezones + 7-day forecast)

**Files:**
- Create: `.config/quickshell/kessel/services/Timezones.qml`
- Modify: `.config/quickshell/kessel/ui/SummaryView.qml`

**Interfaces:**
- Consumes: `Weather.forecast` (existing property, `services/Weather.qml:22`, array of `{ day, max, min, icon }`, up to 7 entries, index 0 = today — confirmed by `TimeRow.qml`'s existing `forecast.slice(1,4)` usage and its comment "skip today, it's the 'now' above").
- Produces (new): `Timezones.wanted: bool` (settable by consumers to gate polling), `Timezones.vienna: string` (`"HH:MM"` or `""` before the first result), `Timezones.sofia: string` (same shape).

- [ ] **Step 1: Write `Timezones.qml`**

```qml
// SPDX-License-Identifier: GPL-3.0-or-later
// Europe/Vienna and Europe/Sofia clocks, via `TZ=<zone> date` (no Intl in
// this QML engine -- confirmed). Polls only while `wanted` is true.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root
    property bool wanted: false
    property string vienna: ""
    property string sofia: ""

    function refresh() { viennaProc.running = true; sofiaProc.running = true }
    Timer { interval: 30000; running: root.wanted; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    Process {
        id: viennaProc
        command: ["env", "TZ=Europe/Vienna", "date", "+%H:%M"]
        stdout: StdioCollector { onStreamFinished: root.vienna = text.trim() }
    }
    Process {
        id: sofiaProc
        command: ["env", "TZ=Europe/Sofia", "date", "+%H:%M"]
        stdout: StdioCollector { onStreamFinished: root.sofia = text.trim() }
    }
}
```

- [ ] **Step 2: Verify the service in isolation**

`island.sh restart` (new `.qml` files need a restart, not just a hot-reload, per this repo's own pitfall notes). Then confirm the two `date` processes actually run only on demand: `qs -c kessel ipc call island perspectiveSet time` won't yet trigger anything (nothing reads `Timezones.wanted` yet) — instead, temporarily confirm via a scratch check: run `TZ=Europe/Vienna date +%H:%M` and `TZ=Europe/Sofia date +%H:%M` directly in a shell and note the values, to compare against Step 4's UI output.

- [ ] **Step 3: Add Time's extra section to `SummaryView.qml`**

Add `readonly property bool isTime: Perspectives.current === "time"` next to `isMusic`. Bind `Timezones.wanted: root.shown && root.isTime` (a plain property assignment on the singleton from within `SummaryView`, same pattern `Cava.wanted` already uses from `MusicRow.qml`). Add a new `Column` as the last child of the existing `col` `Column`, `visible: root.isTime`, `width: parent.width`, containing:
- A `Row` (centered) with three `Chip`s (or `Label`s) showing the local time (`Time.time`, reuse the existing property — this is "home"), `Timezones.vienna`, `Timezones.sofia`, each labeled ("Home"/"Vienna"/"Sofia").
- A `Row` (centered, `spacing` small enough that 7 items fit in ~496px — roughly 70px each) with a `Repeater` over `Weather.forecast.slice(0, 7)`, each delegate showing `modelData.day`, a small `Glyph` for `modelData.icon`, and `modelData.max` — same three-field shape `TimeRow.qml`'s existing forecast `Repeater` already uses, just `slice(0, 7)` instead of `slice(1, 4)` and laid out to fit the fixed width (smaller font/spacing than `TimeRow`'s resting-row version, which has the whole island width to work with).

- [ ] **Step 4: Verify**

`island.sh restart`, `qs -c kessel ipc call island perspectiveSet time`, `qs -c kessel ipc call island glance true`, `grim` a screenshot. Expected: three times shown (local, Vienna, Sofia) matching Step 2's shell values (within a minute), and up to 7 forecast entries (first check `Weather.forecast.length` via `qs -c kessel ipc call island status` or similar live introspection — if it's currently reporting fewer than 7, confirm the row just shows that many with no blank/broken trailing slots, rather than assuming 7 are always present), all within the unchanged 520px width (confirm by comparing the screenshot's card width against Task-free perspectives, e.g. Overview's glance, which should be identically sized). `ps -ef | grep -c '[T]Z=Europe'` right after this must show processes (confirming the poller ran).

Then, **without closing the glance**, switch perspective while still hovering: `qs -c kessel ipc call island perspectiveNext` (or `perspectiveSet overview`) while `glance` is still `true`. Expected: the timezone/forecast section disappears immediately (not left showing stale content for the now-inactive Time perspective), and a follow-up check of running processes shows the `TZ=Europe` `date` calls have stopped recurring (confirms `wanted` reacts to a perspective change mid-hover, not only to the glance closing). Then `qs -c kessel ipc call island glance false`. `qs log -c kessel` clean of new WARN/ERROR throughout.

- [ ] **Step 5: Commit**

```bash
git add .config/quickshell/kessel/services/Timezones.qml .config/quickshell/kessel/ui/SummaryView.qml
git commit -m "island: Time perspective's hover view gets timezones + full forecast"
```

---

### Task 3: Metrics' extra section (bigger charts + top-5 processes)

**Files:**
- Create: `.config/quickshell/kessel/services/Processes.qml`
- Modify: `.config/quickshell/kessel/ui/SummaryView.qml`

**Interfaces:**
- Consumes: `Stats.cpuHist` / `Stats.memHist` / `Stats.rxHist` / `Stats.txHist` (existing properties, `services/Stats.qml:57-60`, 40-sample arrays already feeding the resting row's `Spark` sparklines).
- Produces (new): `Processes.wanted: bool`, `Processes.topCpu: [{name, pct}]` (up to 5, sorted descending), `Processes.topMem: [{name, pct}]` (same shape).

- [ ] **Step 1: Write `Processes.qml`**

```qml
// SPDX-License-Identifier: GPL-3.0-or-later
// Top-5 processes by CPU and by memory, via `ps`. Polls only while `wanted`
// is true -- confirmed live, ~20ms per call, cheap enough for a 3s interval.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root
    property bool wanted: false
    property var topCpu: []
    property var topMem: []

    function parse(text) {
        const out = []
        for (const line of text.trim().split("\n")) {
            const m = line.match(/^(.*\S)\s+([\d.]+)$/)
            if (m) out.push({ name: m[1].trim(), pct: parseFloat(m[2]) })
            if (out.length >= 5) break
        }
        return out
    }
    function refresh() { cpuProc.running = true; memProc.running = true }
    Timer { interval: 3000; running: root.wanted; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    Process {
        id: cpuProc
        command: ["ps", "-e", "-o", "comm,%cpu", "--sort=-%cpu", "--no-headers"]
        stdout: StdioCollector { onStreamFinished: root.topCpu = root.parse(text) }
    }
    Process {
        id: memProc
        command: ["ps", "-e", "-o", "comm,%mem", "--sort=-%mem", "--no-headers"]
        stdout: StdioCollector { onStreamFinished: root.topMem = root.parse(text) }
    }
}
```

- [ ] **Step 2: Verify the service in isolation**

`island.sh restart`. Run `ps -e -o comm,%cpu --sort=-%cpu --no-headers | head -5` directly in a shell and note the top process names/percentages, to compare against Step 4's UI output.

- [ ] **Step 3: Add Metrics' extra section to `SummaryView.qml`**

Add `readonly property bool isSystem: Perspectives.current === "system"` next to `isMusic`/`isTime`. Bind `Processes.wanted: root.shown && root.isSystem`. Add a new `Column`, `visible: root.isSystem`, `width: parent.width`, containing:
- Four bigger `Spark`s (CPU/mem/rx/tx, reusing `Stats.cpuHist` etc. exactly as `SystemRow.qml` already does) at a larger size than the resting row's — e.g. `height: 40` (vs. the default `16`), `barWidth: 3`, `count: 40` (the full history buffer, vs. the default `24`) — each paired with a `Label` naming it, stacked in a `Column` rather than `SystemRow`'s single wide `Row` (fits 520px by going vertical instead of wide).
- Two `Repeater`s side by side (CPU list, memory list — two `Column`s in a `Row`, each roughly 240px wide to fit two side by side within 520px) over `Processes.topCpu` and `Processes.topMem`, each delegate a `Label` or `ListItem`-style row showing `modelData.name` and `modelData.pct.toFixed(1) + "%"`.

- [ ] **Step 4: Verify**

`island.sh restart`, `qs -c kessel ipc call island perspectiveSet system`, `qs -c kessel ipc call island glance true`, `grim` a screenshot. Expected: four enlarged charts and two 5-row process lists, the top entries matching Step 2's shell output (processes can shift slightly between the shell check and the UI poll — confirm the same *top 1-2* names appear, not an exact frozen match; also confirm no row is blank/broken if a process from the list happened to exit between polls — the `parse()` function's regex-match guard should just produce a shorter list, never a broken entry). Confirm width is still 520px (same comparison as Task 2).

While still hovering (glance still `true`), switch perspective to one with no extra section: `qs -c kessel ipc call island perspectiveSet minimal` (or `overview`). Expected, via screenshot: the charts/process-lists section disappears and the glance view's height shrinks back down to baseline-only — no leftover blank space where Metrics' section was (this is the same height-reactivity `col.implicitHeight` already provides elsewhere in this file, but confirm it visually here since this is the first time two different *extra-section* perspectives exist to switch between). Confirm `ps` polling actually stopped: wait a few seconds, then check `ps -ef | grep -c '[-]-sort=-%cpu'` returns to near-zero (one in-flight call from the moment of switching is fine; a steady stream is not). Finally `qs -c kessel ipc call island glance false`. `qs log -c kessel` clean of new WARN/ERROR throughout.

- [ ] **Step 5: Commit**

```bash
git add .config/quickshell/kessel/services/Processes.qml .config/quickshell/kessel/ui/SummaryView.qml
git commit -m "island: Metrics perspective's hover view gets bigger charts + top processes"
```
