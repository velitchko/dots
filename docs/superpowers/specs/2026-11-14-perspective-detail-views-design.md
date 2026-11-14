# Phase 3: perspective-specific hover detail views

> Design doc, agreed in conversation on 2026-11-14 (deferred from the original
> issues.md backlog triage session specifically for its own design pass).

## Intent

Right now, hovering the island shows the exact same `SummaryView` regardless
of which perspective (Overview/Time/Music/Metrics/Minimal) is active — the
baseline only: avatar, time, user + date, weather, a compact now-playing
card if something's playing, and brief CPU/RAM/network chips. Reported as
"the static thing" — the hover view should show more, and different,
information depending on which perspective you're hovering from, while
every perspective keeps that same baseline present.

## Goals

- Every perspective's hover view still shows the baseline (time, user,
  date, weather, now-playing, brief metrics) — consistency was explicitly
  requested, not optional per-perspective.
- Time and Metrics get real additional content, grounded in what's already
  technically available (no speculative integrations).
- Music's now-playing slot gets richer in place (bigger art, full
  album/artist, prev/next, progress), not literally more OR a separate
  section — the user's ask was "more details... from Deezer" referring to
  the now-playing display itself.
- Overview and Minimal get nothing beyond the baseline (confirmed in
  conversation): Overview's resting row already is "a bit of everything",
  and Minimal is deliberately sparse.

## Non-goals / anti-goals

- No Deezer Web API integration (OAuth, stored tokens, a real "favorite"
  call). Confirmed via live D-Bus introspection: Deezer's MPRIS interface
  is 100% standard, no custom favorite property or method exists. Building
  this for real is a separate, much bigger feature (a new auth surface,
  comparable in shape to the AI chat's provider-key setup) — skipped for
  now per the user's explicit choice.
- No change to Overview's or Minimal's hover content.
- Not re-litigating the `Perspectives.qml` list or how perspectives are
  chosen/rotated — this only changes what the hover view shows per
  perspective already selected.

## Constraints / verified technical facts

- **No `Intl` in Quickshell's QML JS engine** (confirmed live: `new
  Intl.DateTimeFormat(...)` throws `ReferenceError: Intl is not defined`).
  Multi-timezone display cannot use the obvious JS approach.
  **Verified working alternative:** `TZ=<iana-zone> date +<format>` via a
  `Process`, which correctly handles DST and zone names using the system's
  own tzdata (tested live for Europe/Vienna and Europe/Sofia).
- **`ps aux --sort=-%cpu`** (or `--sort=-%mem`) runs in ~20ms on this
  machine — cheap enough to poll only while actually visible.
- **Deezer's MPRIS `Metadata`** already includes `xesam:album` and a
  **500×500** `mpris:artUrl`, and the player supports `Next`/`Previous`
  (`CanGoNext`/`CanGoPrevious` both true) — all already reachable from
  `Media.qml`, just not surfaced in any detail view yet. No new dependency
  needed for the richer music display or prev/next buttons.
- **Weather.qml already fetches a full 7-day forecast** (Open-Meteo); only
  3 days are shown anywhere today (`TimeRow.qml`'s resting view). Showing
  more in the hover view needs no new fetching.
- **Stats.qml already keeps 40-sample CPU/mem/rx/tx history arrays** (feeds
  the existing small `Spark` sparklines in `SystemRow.qml`). A bigger chart
  reuses this data; no new collection.
- **No existing "top processes" data anywhere** — this is new.

## Decided (from conversation)

- **Deezer favorite/like:** skipped. Prev/next and richer display only.
- **"Home" timezone:** the system's local timezone (whatever the main
  clock already shows), displayed alongside Vienna and Sofia for
  comparison — not a separately configurable zone.
- **Top processes:** top 5 by CPU and top 5 by memory, as two short lists
  (a process can dominate one without dominating the other).
- **Overview's hover view:** baseline only, nothing added.

## Approach

**Architecture** (mirrors `RestView.qml`'s existing pattern, which already
solves "one shared view, different content per perspective," rather than
inventing a new one): `SummaryView.qml` keeps the baseline layout, and its
now-playing slot and an optional section below the baseline both become
perspective-aware:

- **Now-playing slot:** today it's always a compact `MediaCard`. On the
  Music perspective specifically, swap in a new, richer component instead
  (bigger art from the already-available 500×500 URL, full album/artist,
  prev/next buttons, a progress bar) — everywhere else, the compact card
  stays as-is.
- **Extra section below the baseline** (only present on two perspectives):
  - **Time:** a three-zone row (local / Vienna / Sofia, via the verified
    `TZ=… date` approach, refreshed on a modest timer — seconds precision
    isn't needed) and the already-fetched forecast shown as 7 days
    instead of 3.
  - **Metrics:** larger versions of the existing CPU/mem/network sparkline
    data, plus two "top 5" process lists (CPU, memory) from a new
    `Process`-based poller, gated to run only while this section is
    actually visible (same pattern `Cava.wanted` already uses, gated on
    `root.active && Media.playing`).
  - **Overview, Minimal:** no extra section.

## Resolved after a builder check

- **Width:** `SummaryView` stays fixed at 520px (Phase 2 of this backlog
  pass just fixed exactly this — a hover view whose width varied by
  perspective — so it shouldn't regress here). Time's and Metrics' extra
  sections lay out vertically and use compact row layouts to fit within
  that width; height already grows with content today (`col.implicitHeight
  + 24`) and continues to.
- **Music's "richer component":** not a new file. `MediaCard.qml` already
  has prev/next and a progress bar with elapsed/remaining time in both
  `compact` modes — only `implicitHeight` (92 vs 104) differs. The Music
  perspective's now-playing slot becomes `MediaCard { compact: false }`
  (already used as-is in `ControlCenter.qml`) plus showing `Media.album`
  (exposed on the singleton, currently unused anywhere) and a modestly
  bigger art tile. Everywhere else keeps the existing compact card.

## What's left to the builder

- Exact visual layout/spacing of the new sections (within this repo's
  existing component vocabulary: `Chip`, `Spark`, `Label`, `Row`/`Column`)
  — a UI detail, not a design decision.
- The poll interval for the timezone row and the top-processes list
  (cheap enough that this is a judgment call, not a performance concern —
  confirmed both are cheap operations).
