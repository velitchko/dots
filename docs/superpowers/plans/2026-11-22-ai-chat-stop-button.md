# AI chat stop button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user cancel an in-flight AI chat reply from the panel UI instead of being stuck waiting for it to finish.

**Architecture:** `AiChat.qml` gains a `stop()` function that kills the in-flight `sendProcess` (SIGTERM via Quickshell's `Process.running = false`) without triggering the existing "exited unexpectedly" error path, then commits whatever streamed so far through the normal clean-finish path (or drops an empty placeholder). `AiChatWindow.qml` swaps the send button to a stop icon while streaming.

**Tech Stack:** QML (Quickshell), no new dependencies.

**Spec:** Approved inline in conversation (small change; no separate spec doc — see chat history 2026-11-22): add `AiChat.stop()` and wire it to the send button's icon/action while `streaming` is true.

## Global Constraints

- No new Nerd Font codepoint — reuse the already-verified `Icons.stop` (`.config/quickshell/kessel/Icons.qml:26`).
- Killing `sendProcess` must not also fire `sendProcess.onExited`'s existing "the response process exited unexpectedly" error path (`services/AiChat.qml:225-227`).
- This repo has no QML unit-test framework; validation is `island.sh restart` + `qs log -c kessel` + manual IPC/UI exercise, per AGENTS.md.

## Review Focus

- Stopping before any delta ever arrived (`streamingText === ""`) must not leave a permanent blank assistant bubble in history.
- Stopping must re-enable the input field and session switching (both gated on `AiChat.streaming`) once the stop completes.
- Clicking stop twice, or stop followed immediately by a real process exit, must not double-run `_finishStreaming`.
- The partial reply must still go through markdown rendering (`renderProcess`), not get stuck as raw/unrendered text.
- `saveHistory()` must still run after a stopped reply, so a stop survives a shell restart.

---

### Task 1: `AiChat.stop()` + stop button

**Files:**
- Modify: `.config/quickshell/kessel/services/AiChat.qml`
- Modify: `.config/quickshell/kessel/ui/AiChatWindow.qml`

**Interfaces:**
- Produces: `AiChat.stop()` — callable with no arguments, valid any time (no-ops if `!root.streaming`).

- [ ] **Step 1: Implement `stop()` in `services/AiChat.qml`**, placed next to `send()`:
  - If `!root.streaming`, return.
  - Set `sendProcess.gotFinalChunk = true` first (so `onExited` takes the "already handled" branch instead of calling `_finishStreaming` with an error).
  - `sendProcess.running = false` (Quickshell `Process`: setting this terminates the child process).
  - If `root.streamingText.trim() === ""`: drop the trailing empty assistant placeholder — `root._setMessages(root.messages.slice(0, -1))`, then `root.streaming = false; root.saveHistory()`.
  - Else: call `root._finishStreaming(undefined)` (existing clean-finish path: commits `streamingText` into the message, clears it, kicks off `renderProcess`, and `_applyRenderedHtml` will clear `streaming` and `saveHistory()` once rendering finishes — matching the normal completion flow exactly).

- [ ] **Step 2: Wire the stop button in `ui/AiChatWindow.qml`** (the `IconButton` at line 312, next to `SearchField { id: input }`):
  - `icon: AiChat.streaming ? Icons.stop : Icons.send`
  - `onClicked: AiChat.streaming ? AiChat.stop() : input.accepted()`

- [ ] **Step 3: Validate config loads clean**

Run: `KESSEL_STRICT=1 Hyprland --verify-config -c ~/.config/hypr/hyprland.lua`
Expected: `config ok`

- [ ] **Step 4: Reload the island and check for new warnings/errors**

Run: `~/.config/hypr/scripts/island.sh restart && sleep 3 && qs log -c kessel | grep -E 'WARN|ERROR|caused'`
Expected: nothing new attributable to `AiChat.qml`/`AiChatWindow.qml`.

- [ ] **Step 5: Exercise it for real** — open the panel (`qs -c kessel ipc call <toggle entry for aiChatToggle>` or `SUPER+I`), send a prompt to a provider/model that's slow enough to click stop mid-stream, click the stop button partway through, and confirm: the button showed the stop icon while streaming, the partial reply is kept (not replaced by an error), it's rendered (not raw markdown), the input field re-enables, and a second message can be sent afterward. Also test clicking stop immediately after sending (before any delta arrives) and confirm no blank bubble is left. Take a screenshot (`grim -g "x,y wxh" file.png`) of the mid-stream stop state. Report results — this can't be fully scripted.

- [ ] **Step 6: Commit**

```bash
git add .config/quickshell/kessel/services/AiChat.qml .config/quickshell/kessel/ui/AiChatWindow.qml
git commit -m "ai chat: add a stop button to cancel an in-flight reply"
```
