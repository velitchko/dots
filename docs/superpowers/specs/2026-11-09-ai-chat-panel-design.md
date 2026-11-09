# AI chat panel — design

**Tracked as:** issue #2, `docs/backlog/ai-chat.md`.
**Status:** approved to build (human partner opted out of the brainstorming Q&A and asked to be pinged when there's something to check out — this doc records the calls made in that gap, not a negotiated agreement).

## Intent

A floating AI chat window for the desktop: ask a question, get a streamed answer with real markdown and math rendering, without leaving the keyboard or opening a browser tab.

## Goals

- Open/close with a dedicated keybind (`SUPER + I`), independent of the island's panel system.
- A real floating window: draggable, resizable, alt-tabbable — not a fixed overlay.
- Markdown (code blocks with syntax highlighting, tables, lists) and LaTeX math rendered properly, not as raw text.
- Copy a message, quote a message into the input, keep replying in the same thread.
- Multiple providers, chosen per-conversation: local (Ollama) and API-key-based remote (Anthropic, OpenAI). New providers addable without touching the window's UI code.
- API keys live in the system keyring (libsecret/Secret Service), never in the repo or in plain config.
- Off by default: nothing contacts a remote provider until the user configures one. Local-only (Ollama) use should also work with zero cloud calls.
- A short conversation history on disk, so the window reopens where you left off.

## Non-goals

- Claude or ChatGPT subscription login. **Investigated and closed**: Anthropic's own Claude Code legal docs prohibit third-party apps from offering Claude.ai login or routing requests through subscription-plan credentials; OpenAI's equivalent ("Sign in with ChatGPT" plan usage) is a partner-only waitlist. Both providers are API-key only here.
- Multi-window chat (several conversations open at once), tabs, or a conversation browser/search UI. One window, one active thread, switchable history later if asked for.
- Voice input/output, image generation, file upload/RAG. Text in, text out.
- A general-purpose plugin SDK for third-party provider plugins. "Addable without touching the window's UI code" means a new backend script + a config entry, not a public extension API.

## Anti-goals (would make this a failure even if it "works")

- Any network call to a provider the user hasn't explicitly configured.
- A secret ever touching the repo, a dotfile under version control, or a log file.
- The window blocking or stealing focus from whatever the user was doing when it's closed.

## Architecture decisions (mine to make, recorded here)

**Window type — a real floating Hyprland window, not a layer-shell panel.** The island's panels (`ui/panels/*.qml`) are `Loader`ed inside `Island.qml`'s single `PanelWindow` (layer-shell, fixed anchors, no user dragging). "Hovering/floating... stays open" means normal window semantics: draggable, resizable, closable, alt-tabbable. A plain `QtQuick.Window` (not `PanelWindow`/layer-shell), rendered as an ordinary xdg-toplevel, gets this from Hyprland's existing floating-window handling — but **only with an explicit window rule**: `workspaces.lua` tiles everything by default, and every other float-by-default utility window (pavucontrol, the polkit agent, OmniGlyph) has its own `hl.window_rule({ match = {...}, float = true, center = true })`. This window needs one too, matched by **title** (`"Kessel AI Chat"`), not class — Quickshell windows in the same process don't reliably get distinct `app_id`s. Without this rule the window would tile into the layout on open, the opposite of the goal. It is a new top-level item instantiated from `shell.qml`, lazily (see below) — not a second Quickshell config; see the rendering decision below for why process-splitting doesn't actually buy the crash-isolation `kessel-lock` has.

**Loading — lazy, via `LazyLoader`**, the same pattern `kessel-lock/shell.qml` already uses for the real lock surface (`LazyLoader { active: ... }`). The window (and everything in it) is only constructed on the first `SUPER + I`, not at shell startup — this matters more here than usual given the rendering decision below.

**Rendering — QtQuick's native `Text.MarkdownText`, not an embedded browser engine. This reverses the original plan in this doc after a spike proved the browser-engine approach doesn't work at all, not just "is heavier than ideal":**

A throwaway `WebEngineView` embedded in a minimal Quickshell config crashed the entire process on load: `FATAL: Argument list is empty, the program name is not passed to QCoreApplication. base::CommandLine cannot be properly initialized.` This is Chromium's own guard for a documented Qt requirement — `QtWebEngineQuick::initialize()` must run *before* `QGuiApplication` is constructed — and Quickshell's `qs` binary doesn't do that (it can't know ahead of time that a shell's QML will want WebEngine). The same plain QML loaded fine under Qt's own `qml6` runtime, confirming the blocker is specifically "hosted inside Quickshell," not the GPU/Wayland/sandbox environment. **Critically, this isn't fixed by splitting into a second Quickshell config like `kessel-lock`** — a second config still runs via the same `qs` binary with the same missing initialization call, so it would crash identically. Patching/rebuilding Quickshell itself is out of scope for a dotfiles repo. WebEngineView is off the table entirely, in-process or out.

The replacement, spiked and confirmed working (screenshot on file): `Text { textFormat: Text.MarkdownText }`, a built-in QtQuick feature since 5.14, handles headings, bold/italic, inline code, fenced code blocks (as plain monospace — no per-language syntax coloring, Qt doesn't ship a highlighter), bullet/numbered lists, **tables** (rendered as a bordered grid, better than expected), and links, all for free, with zero new dependencies and zero crash risk. It does **not** render LaTeX/math at all — `$E = mc^2$` shows up as that literal text, unstyled.

This is a real, smaller scope than originally promised on two fronts (code blocks are plain mono, not syntax-colored; math doesn't typeset), and I'm not picking a workaround for either without your call — see **Decision needed**, below, before the plan locks in Task scope for the rendering piece. Styling (fonts, colors, spacing around the native markdown text) still needs to match the rest of the shell — see the dots-aesthetics note at the end of this doc.

**Provider calls — a Python helper script per request, not QML doing HTTP.** Nothing else in kessel does raw streaming HTTP from QML (the existing pattern is: QML spawns a `Process`, a script does the real work, QML consumes its output — see `services/Privacy.qml`'s camera probe, `services/Updates.qml`). A single script, `scripts/desktop/ai-chat.py`, takes `--provider <name> --model <model>` on argv and the conversation as JSON on stdin, and streams newline-delimited JSON chunks (`{"delta": "..."}` ... `{"done": true}`) to stdout as the provider streams its response. One script, three provider backends inside it (`ollama`, `anthropic`, `openai`) sharing the same stdin/stdout contract, selected by `--provider`; adding a fourth later means adding a branch here, not touching QML.

**Secrets — libsecret via `secret-tool`, already live on this system.** `secret-tool store/lookup --label "kessel-ai-<provider>" service kessel-ai provider <provider>` against the already-running `org.freedesktop.secrets` (GNOME Keyring) service. The Python script looks keys up this way at call time; nothing resembling a key is ever written to a QML property, a log, or a file this repo tracks.

**History — plain JSON on disk**, `~/.local/state/kessel/ai/history.json`: one file, an array of `{role, content, provider, ts}` messages for the single active thread. No database; this is a short, single-thread history per the non-goals above, not an archive.

**State/IPC — a new singleton, `services/AiChat.qml`**, holding `shown`, `provider`, `model`, `messages`, `streaming`. Per `AGENTS.md`'s own convention ("an IPC function in IslandState.qml if it's scriptable" — true for every existing feature regardless of which singleton owns its state, e.g. `timer()` lives in `IslandState.qml` and delegates to `Timers.qml`), the IPC entry points (`aiChatToggle`, `aiChatOpen`, `aiChatClose`) are added to `IslandState.qml`'s existing `IpcHandler` (target `island`) and delegate to `AiChat.*`. This means `scripts/desktop/island-or.sh` and the existing `island(fn, fallback)` keybind helper work unmodified — the keybind is `island("aiChatToggle")` like any other.

**No fallback for the `SUPER + I` bind.** `AGENTS.md` asks every key-bound island feature to have a non-Quickshell fallback; every other `island(...)` call in `keybinds.lua` provides one (`fuzzel`, `pavucontrol`, ...). There's no sensible equivalent here — nothing else on the system renders this panel. Deliberate exception, not an oversight.

**Settings (API key entry/removal) live inside the AiChat window itself**, not in `ControlCenter.qml` / `IslandState.panels`. The whole point of decoupling this from the island's panel system is that it's not reached by digging through Control Center; a gear icon in the chat window's own toolbar opens an inline settings view in the same window. Visually it still borrows the panel's look (`Theme.*`, `components/*`), just not its navigation.

## Dots aesthetic — this has to look like the rest of kessel

Same visual system as everywhere else in this repo, not a bolted-on style: `Theme.qml` colors (including `Theme.borderWidth`, `Theme.radiusPanel`/`radiusCard`, the `Theme.island` material), `Theme.font`/`Theme.iconFont`, and existing `components/*` (`Label`, `Glyph`, `Bar`, `SearchField`, `IconButton`) wherever one already does the job — no new one-off button/input styles invented for this window. The one real design choice specific to this feature: does it read as *part of the island family* (same pill/capsule language, `Theme.island` background, same rounded-capsule chrome as `Island.qml`'s pill) or as its own distinct window chrome since it's explicitly *not* an island panel? My call: same family — `Theme.island` background, `Theme.radiusPanel` corners, `Theme.borderWidth` border — it's a sibling surface, not a different app. Message bubbles use `Theme.card`/`Theme.cardHi` as cards already do elsewhere (e.g. `NotesPanel.qml`'s kanban cards).

## Decision needed

The rendering spike (above) cut real scope from the original ask. Two independent calls, your preference on each:

1. **Syntax-highlighted code blocks.** Native markdown gives plain monospace fenced code (no color). Getting real per-language highlighting back means either (a) skip it for v1 — plain mono, ship now, revisit later if it bothers you in practice, or (b) have `ai-chat.py` pre-highlight code blocks server-side (e.g. with `pygments`, converting to a small set of QML-renderable styled spans) before the message ever reaches QML — real color, meaningfully more code in the backend script and the QML↔script message format.
2. **LaTeX/math rendering.** Native markdown doesn't typeset math at all — it shows the raw `$...$` source. Getting real typesetting back without a browser engine means pre-rendering each math expression to a small SVG via a script (e.g. `matplotlib` or a `katex` CLI if one's available packaged) and splicing an `Image` into the message where the `Text` would otherwise show raw LaTeX — a real per-message async rendering pipeline, not a QML property. Alternative: skip math rendering for v1, same as code highlighting above.

I'd default to (a) — skip both for v1, ship the window with correct everything-else markdown now, add real code-highlight/math rendering as a follow-up only if it turns out to matter in practice — since both "real" versions are a meaningful chunk of additional engineering for features that may or may not come up often in your actual usage. But this changes what the plan below actually builds, so it's your call, not mine.

## Constraints carried from the issue

- Off by default; no network traffic unless a provider is explicitly configured.
- API keys in the system keyring, never in the repo.
- Local-first: Ollama works with zero cloud calls.
- GPL-3.0-or-later; SPDX header on new files.
- `AGENTS.md` validation conventions apply (`KESSEL_STRICT=1 Hyprland --verify-config`, `qs log -c kessel` clean, exercise via IPC + screenshot — this repo has no QML unit test harness, so "tests" for the QML side are the same manual IPC+screenshot exercises every other feature in this repo is verified with, not a fabricated test suite).

## What's left to the builder

Exact QML property names beyond what's pinned above, the exact `ai-chat.py` argument parsing and error handling, window sizing/positioning defaults, and the exact layout of the in-window settings view (placement decided above; the precise fields/spacing are not).
