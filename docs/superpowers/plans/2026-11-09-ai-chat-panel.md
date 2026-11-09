# AI Chat Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A floating, draggable chat window (`SUPER + I`) for talking to local (Ollama) or API-key-based remote (Anthropic, OpenAI) models, with real syntax-highlighted code and real typeset LaTeX math in responses, no subscription login, keys in the system keyring.

**Architecture:** A lazily-loaded plain `QtQuick.Window` (not a layer-shell panel) instantiated from `shell.qml`, floated by an explicit Hyprland window rule. QML spawns `scripts/desktop/ai-chat.py` per request (one process per send), which streams raw text deltas live, then is re-invoked once in `--render` mode on the complete message to produce Qt-rich-text-safe HTML (markdown + pygments syntax highlighting + matplotlib-rendered math spliced in as file-referenced PNGs). State lives in a new `services/AiChat.qml` singleton; its IPC entry points are added to `IslandState.qml`'s existing `IpcHandler` so `keybinds.lua`'s `island(fn)` helper works unmodified. API keys never reach QML, a log, or a file this repo tracks — `ai-chat.py` looks them up from `secret-tool` at call time.

**Tech Stack:** QML/Quickshell (existing stack), Python 3 + `requests` (provider HTTP/streaming) + `markdown` (`fenced_code`, `codehilite`, `tables` extensions) + `pygments` (via `codehilite`) + `matplotlib` (`mathtext` → PNG) + `secret-tool`/libsecret (already running as a system service on this machine).

**Spec:** `docs/superpowers/specs/2026-11-09-ai-chat-panel-design.md`

## Global Constraints

- Off by default: zero network traffic until a provider is explicitly configured (Ollama still counts as "configured" once its model is picked — it's local, but still an explicit user action).
- No API key ever appears in a QML property that gets logged, in `qs log -c kessel` output, in `ps aux` (i.e. never pass a key as a process argv — `secret-tool` takes secrets via stdin), or in any file this repo tracks.
- No subscription login (Claude or ChatGPT) anywhere in this feature — API keys only, per the spec's closed investigation.
- SPDX header (`GPL-3.0-or-later`) on every new file.
- New system packages go in `pkglist.txt` (official `extra` repo only, no AUR needed for this feature): `python`, `python-requests`, `python-markdown`, `python-pygments`, `python-matplotlib`.
- Visual language matches the rest of kessel: `Theme.qml` tokens and existing `components/*` only — no new one-off styled controls.
- `AGENTS.md` validation applies throughout: `KESSEL_STRICT=1 Hyprland --verify-config -c ~/.config/hypr/hyprland.lua` after any `.lua` change, `bash -n`/syntax checks, `qs log -c kessel | grep -E 'WARN|ERROR|caused'` clean after every QML change, and `island.sh restart` + IPC + a screenshot to actually exercise each QML task — this repo has no QML unit-test harness, so QML "tests" below are that same manual exercise, not a fabricated suite.

## Review Focus

- **No API key configured, provider selected anyway.** A reasonable person expects a clear in-chat message ("No API key set for Anthropic — add one in Settings"), not a hang, a crash, or a silent no-op. Owned by Task 2 (`ai-chat.py` exits cleanly with an `{"error": ...}` chunk when `secret-tool lookup` finds nothing) and Task 8 (QML surfaces that error chunk as a message, doesn't just stop the spinner).
- **The model's own response contains HTML-special characters or literal HTML/script-looking text** (very plausible — code samples routinely contain `<`, `>`, `&`; a response could even contain literal `<script>` as example text). A reasonable person expects it displayed as inert text, not interpreted as markup or allowed to inject into the rich-text view. Owned by Task 1 (`render_markdown` escapes raw text before any markdown/HTML construction — tested explicitly with `<script>alert(1)</script>` and bare `&`/`<`/`>` in both prose and inside a fenced code block).
- **Mid-stream provider error** (Ollama not running, API key rejected with 401, network drops). A reasonable person expects the partial response to stay visible with a clear error appended, not a stuck spinner or a crashed window. Owned by Task 2 (catch and emit `{"error": ...}` instead of letting an exception kill the process) and Task 8 (render it, re-enable the input).
- **Malformed/unbalanced markdown or LaTeX** (an unclosed code fence, an unmatched `$`, a `$` that's actually a currency sign, not math). A reasonable person expects it to degrade to readable text, not corrupt the whole message's rendering or hang the regex extraction. Owned by Task 1, tested with each case explicitly (unmatched `$42 and $7`, unclosed ` ``` `).
- **Secret storage never leaks the key via argv.** A reasonable person storing an API key expects it invisible to `ps aux`/shell history, not just "not committed to git." Owned by Task 3, tested by asserting the key is passed via the subprocess's stdin, never appears in the constructed argv list.

---

## Task 1: Markdown + math rendering pipeline

**Files:**
- Create: `scripts/desktop/ai-chat.py` (this task only adds the rendering half; Task 2 adds the CLI/provider half to the same file)
- Test: `scripts/desktop/test_ai_chat.py`

**Interfaces:**
- Produces: `render_markdown(text: str, *, text_color: str = "#e8e8e8", math_dir: str) -> str` — returns Qt-`Text.RichText`-safe HTML. `math_dir` is a directory the function may write math PNGs into (caller-provided, so tests can point it at a temp dir and the real CLI can point it at a per-conversation scratch dir under `~/.local/state/kessel/ai/math/`).
- Consumes: nothing from other tasks.

- [ ] **Step 1: Write the failing tests**

```python
# scripts/desktop/test_ai_chat.py
import re
from ai_chat import render_markdown

def test_basic_markdown(tmp_path):
    html = render_markdown("# Hi\n\n**bold** and *italic*.", math_dir=str(tmp_path))
    assert "<h1>Hi</h1>" in html
    assert "<strong>bold</strong>" in html
    assert "<em>italic</em>" in html

def test_code_block_is_syntax_highlighted(tmp_path):
    html = render_markdown("```python\ndef f():\n    pass\n```", math_dir=str(tmp_path))
    assert "color:" in html or "color :" in html  # pygments inline style present
    assert "<span" in html

def test_html_in_prose_is_escaped(tmp_path):
    html = render_markdown("<script>alert(1)</script> & stuff", math_dir=str(tmp_path))
    assert "<script>" not in html
    assert "&lt;script&gt;" in html

def test_html_inside_code_block_is_escaped(tmp_path):
    html = render_markdown("```html\n<script>alert(1)</script>\n```", math_dir=str(tmp_path))
    assert "<script>alert" not in html
    assert "&lt;script&gt;" in html

def test_math_renders_to_file_referenced_png(tmp_path):
    html = render_markdown("Inline math: $E = mc^2$ done.", math_dir=str(tmp_path))
    m = re.search(r'<img src="file://([^"]+\.png)"', html)
    assert m, html
    import os
    assert os.path.isfile(m.group(1))

def test_unmatched_dollar_is_left_as_text(tmp_path):
    html = render_markdown("Costs $42 and $7, not math.", math_dir=str(tmp_path))
    assert "$42" in html
    assert "<img" not in html

def test_unclosed_code_fence_does_not_raise(tmp_path):
    render_markdown("```python\ndef f():\n    pass", math_dir=str(tmp_path))  # must not raise

def test_table_renders_with_visible_borders(tmp_path):
    html = render_markdown("| a | b |\n|---|---|\n| 1 | 2 |", math_dir=str(tmp_path))
    assert "border" in html
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/dot-files/scripts/desktop && python3 -m pytest test_ai_chat.py -v`
Expected: FAIL (`ai_chat` module / `render_markdown` not defined)

- [ ] **Step 3: Implement `render_markdown` in `scripts/desktop/ai-chat.py`**

SPDX header first. Approach (spiked and confirmed working against this exact Qt version — see the design doc for the screenshot evidence): extract `$...$`/`$$...$$` math spans by regex *before* handing the rest to the markdown converter, rendering each with `matplotlib.pyplot` (`matplotlib.use("agg")`, `mathtext.fontset`, `fig.text(..., color=text_color)`, `fig.savefig(..., transparent=True)` to a PNG under `math_dir`), and splicing each back in as `<img src="file://{path}">` in place of a placeholder token (the same placeholder-token technique avoids clashes with markdown's own inline-code escaping — don't math-extract text that's already inside a fenced code block, since `$` there is literal). A span that doesn't parse as valid mathtext (e.g. `$42 and $7` — no closing-within-reasonable-span, or a LaTeX parse error) is left as plain text, not raised. Markdown conversion itself: `markdown.Markdown(extensions=["fenced_code", "codehilite", "tables"], extension_configs={"codehilite": {"noclasses": True, "pygments_style": "monokai"}})`. After conversion, replace Qt's bare `<table>` with an inline-styled one (`<table style="border-collapse:collapse;border:1px solid #555">` and the same on `<td>`/`<th>`, since the plain `border` HTML attribute doesn't render visibly in Qt's rich-text engine, per the spec's spike notes) — a string replace on the markdown library's fixed table-tag output is sufficient, no HTML parser needed. Raw angle brackets and `&` in message text must never reach the output unescaped outside of what `markdown`/`codehilite` themselves already escape — `python-markdown` escapes prose and fenced-code content by default, so this is mostly "don't bypass that," not new code to write; the test in Step 1 is what proves it, not a separate escaping pass.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ~/dot-files/scripts/desktop && python3 -m pytest test_ai_chat.py -v`
Expected: PASS, all 8

- [ ] **Step 5: Add new dependencies to `pkglist.txt`**

Add `python`, `python-markdown`, `python-pygments`, `python-matplotlib` (each with a one-line comment: `# AI chat panel: markdown/syntax-highlight/math rendering`), alphabetically grouped with the file's existing convention.

- [ ] **Step 6: Commit**

```bash
git add scripts/desktop/ai-chat.py scripts/desktop/test_ai_chat.py pkglist.txt
git commit -m "ai-chat: markdown + syntax-highlighted code + math rendering pipeline"
```

## Task 2: Provider streaming + CLI

**Files:**
- Modify: `scripts/desktop/ai-chat.py` (adds the CLI entry point and provider backends around Task 1's `render_markdown`)
- Modify: `scripts/desktop/test_ai_chat.py`

**Interfaces:**
- Consumes: `render_markdown(text, *, text_color, math_dir)` from Task 1.
- Produces: the script's CLI contract, which Task 6 (QML) depends on exactly:
  - `ai-chat.py --provider {ollama,anthropic,openai} --model <name>` reads a JSON array of `{"role": "user"|"assistant", "content": str}` from stdin (the whole conversation so far, including the new user turn), writes newline-delimited JSON to stdout as it streams: `{"delta": "<raw text chunk>"}` repeatedly, then exactly one of `{"done": true}` or `{"error": "<message>"}` as the last line, then exits 0.
  - `ai-chat.py --render` reads a single complete message's raw text from stdin, writes one line of JSON to stdout: `{"html": "<rendered>"}`, then exits 0. (This is what Task 6 calls once streaming finishes, per the spec's "stream raw, re-render once done" split — keeps `render_markdown` out of the per-token hot path.)
  - A missing API key (Anthropic/OpenAI) is not an exception: emit `{"error": "No API key configured for <provider> — add one in Settings"}` and exit 0.
- Produces: `get_key(provider: str) -> str | None`, calling `secret-tool lookup service kessel-ai provider <provider>` via `subprocess.run` (capture stdout, return `None` on nonzero exit instead of raising — "no key yet" is an expected state, not an error).

- [ ] **Step 1: Write the failing tests**

```python
# additions to scripts/desktop/test_ai_chat.py
import json, subprocess, sys

def run_cli(args, stdin_text):
    return subprocess.run([sys.executable, "ai-chat.py", *args], input=stdin_text,
                           capture_output=True, text=True, cwd="scripts/desktop" if False else None)

def test_render_mode_returns_html_json():
    import ai_chat
    out = ai_chat.render_mode("**bold**")
    assert json.loads(out)["html"].count("<strong>") == 1

def test_missing_key_emits_error_not_exception(monkeypatch):
    import ai_chat
    monkeypatch.setattr(ai_chat, "get_key", lambda provider: None)
    chunks = list(ai_chat.stream_anthropic(model="claude-x", messages=[{"role": "user", "content": "hi"}]))
    assert any("error" in c and "API key" in c["error"] for c in chunks)

def test_get_key_returns_none_on_missing_secret(monkeypatch):
    import ai_chat, subprocess as sp
    monkeypatch.setattr(sp, "run", lambda *a, **k: sp.CompletedProcess(a, 1, "", ""))
    assert ai_chat.get_key("anthropic") is None

def test_get_key_passes_secret_via_stdin_never_argv(monkeypatch):
    # storing/looking up must never put a key value in the argv list (ps aux exposure)
    import ai_chat, subprocess as sp
    captured = {}
    def fake_run(args, **kwargs):
        captured["args"] = args
        captured["input"] = kwargs.get("input")
        return sp.CompletedProcess(args, 0, "dummy-key-value\n", "")
    monkeypatch.setattr(sp, "run", fake_run)
    ai_chat.get_key("anthropic")
    assert "dummy-key-value" not in captured["args"]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/dot-files/scripts/desktop && python3 -m pytest test_ai_chat.py -v`
Expected: FAIL (`render_mode`, `stream_anthropic`, `get_key` not defined)

- [ ] **Step 3: Implement the CLI and provider backends in `scripts/desktop/ai-chat.py`**

`get_key(provider)`: `subprocess.run(["secret-tool", "lookup", "service", "kessel-ai", "provider", provider], capture_output=True, text=True)`; return `result.stdout.strip() or None` if `returncode == 0` else `None`. (Lookup never needs stdin — only `store`, used by Task 3, takes the secret that way.)

Three generator functions, each `-> Iterator[dict]` yielding `{"delta": str}` then one final `{"done": True}` or `{"error": str}`:
- `stream_ollama(model, messages)`: POST to `http://localhost:11434/api/chat` with `{"model": model, "messages": messages, "stream": True}`, `requests.post(..., stream=True)`, iterate `response.iter_lines()`, each line is a JSON object with a `message.content` delta; yield `{"delta": ...}` per line, `{"done": True}` when the stream's own `"done": true` arrives. Catch `requests.ConnectionError` → `{"error": "Ollama isn't running (localhost:11434)"}`.
- `stream_anthropic(model, messages)`: `get_key("anthropic")`; if `None`, yield the error chunk and return. Else POST to `https://api.anthropic.com/v1/messages` with the `x-api-key` header and `"stream": True`, parse Anthropic's SSE `content_block_delta` events for `text_delta.text`.
- `stream_openai(model, messages)`: same shape against `https://api.openai.com/v1/chat/completions`, `Authorization: Bearer <key>` header, OpenAI's SSE `choices[0].delta.content`.

`render_mode(text)`: calls `render_markdown` from Task 1 with a fixed `math_dir` (`~/.local/state/kessel/ai/math/`, created if missing) and returns `json.dumps({"html": html})`.

`main()`: `argparse` with `--provider`, `--model`, `--render` (mutually exclusive with `--provider`/`--model`). In provider mode: read stdin as JSON (`messages = json.loads(sys.stdin.read())`), dispatch to the matching `stream_*` function, `print(json.dumps(chunk), flush=True)` per yielded chunk — `flush=True` is load-bearing, this is what makes it actually stream to the QML `Process` reading it live rather than buffering. In render mode: read stdin as plain text, `print(render_mode(text))`. Guard with `if __name__ == "__main__": main()` so the test file's `import ai_chat` doesn't execute the CLI.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ~/dot-files/scripts/desktop && python3 -m pytest test_ai_chat.py -v`
Expected: PASS, all 12 (8 from Task 1 + 4 new)

- [ ] **Step 5: Add `python-requests` to `pkglist.txt`**

- [ ] **Step 6: Manual smoke test against real Ollama, if installed**

Run: `echo '[{"role":"user","content":"say hi in 3 words"}]' | python3 scripts/desktop/ai-chat.py --provider ollama --model <any locally-pulled model>`
Expected: a stream of `{"delta": ...}` lines ending in `{"done": true}`, printed live (not all at once at exit) — confirm by eye that output appears incrementally, not in one burst.
If Ollama/no model is available on this machine, state that explicitly instead of claiming this step passed.

- [ ] **Step 7: Commit**

```bash
git add scripts/desktop/ai-chat.py scripts/desktop/test_ai_chat.py pkglist.txt
git commit -m "ai-chat: streaming provider backends (ollama/anthropic/openai) + render CLI mode"
```

## Task 3: Secret storage (store/delete)

**Files:**
- Modify: `scripts/desktop/ai-chat.py`
- Modify: `scripts/desktop/test_ai_chat.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `store_key(provider: str, key: str) -> None` and `delete_key(provider: str) -> None`, called directly by QML (Task 9) via `Quickshell.Io.Process`, not through the streaming CLI — these are one-off admin actions, not part of the chat request/response loop.
- CLI additions: `ai-chat.py --store-key <provider>` (reads the key from stdin, one line, trailing newline stripped) and `ai-chat.py --delete-key <provider>`.

- [ ] **Step 1: Write the failing tests**

```python
def test_store_key_passes_secret_via_stdin_not_argv(monkeypatch):
    import ai_chat, subprocess as sp
    captured = {}
    def fake_run(args, **kwargs):
        captured["args"] = args
        captured["input"] = kwargs.get("input")
        return sp.CompletedProcess(args, 0, "", "")
    monkeypatch.setattr(sp, "run", fake_run)
    ai_chat.store_key("anthropic", "sk-super-secret-value")
    assert "sk-super-secret-value" not in captured["args"]
    assert captured["input"] == "sk-super-secret-value"

def test_delete_key_calls_secret_tool_clear(monkeypatch):
    import ai_chat, subprocess as sp
    captured = {}
    monkeypatch.setattr(sp, "run", lambda args, **k: captured.setdefault("args", args) or sp.CompletedProcess(args, 0, "", ""))
    ai_chat.delete_key("anthropic")
    assert captured["args"][:2] == ["secret-tool", "clear"]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/dot-files/scripts/desktop && python3 -m pytest test_ai_chat.py -v`
Expected: FAIL (`store_key`, `delete_key` not defined)

- [ ] **Step 3: Implement `store_key`/`delete_key` and the two CLI flags**

`store_key(provider, key)`: `subprocess.run(["secret-tool", "store", "--label", f"kessel-ai-{provider}", "service", "kessel-ai", "provider", provider], input=key, text=True)`. `delete_key(provider)`: `subprocess.run(["secret-tool", "clear", "service", "kessel-ai", "provider", provider])`. Wire both into `main()`'s `argparse` (reading the key for `--store-key` from `sys.stdin.readline().rstrip("\n")`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ~/dot-files/scripts/desktop && python3 -m pytest test_ai_chat.py -v`
Expected: PASS, all 14

- [ ] **Step 5: Manual smoke test**

Run: `echo -n "test-value-123" | python3 scripts/desktop/ai-chat.py --store-key test-provider && secret-tool lookup service kessel-ai provider test-provider && python3 scripts/desktop/ai-chat.py --delete-key test-provider && secret-tool lookup service kessel-ai provider test-provider; echo "exit: $?"`
Expected: the lookup prints `test-value-123` after store, and fails (nonzero exit, no output) after delete.

- [ ] **Step 6: Commit**

```bash
git add scripts/desktop/ai-chat.py scripts/desktop/test_ai_chat.py
git commit -m "ai-chat: secret-tool store/delete for API keys"
```

## Task 4: Hyprland float rule for the chat window

**Files:**
- Modify: `.config/hypr/workspaces.lua`

**Interfaces:**
- Consumes: nothing (Task 8 will create a window titled exactly `"Kessel AI Chat"`, which this rule must match).
- Produces: the window floats and centers on open instead of tiling.

- [ ] **Step 1: Add the window rule**

Add, next to the existing float-by-default rules (pavucontrol, polkit agent, OmniGlyph):

```lua
hl.window_rule({
    name  = "ai-chat-float",
    match = { title = "^Kessel AI Chat$" },
    float = true, center = true,
})
```

- [ ] **Step 2: Verify config**

Run: `KESSEL_STRICT=1 Hyprland --verify-config -c ~/.config/hypr/hyprland.lua`
Expected: `config ok`

- [ ] **Step 3: Commit**

```bash
git add .config/hypr/workspaces.lua
git commit -m "hypr: float the AI chat window instead of tiling it"
```

(Full manual verification — actually opening the window and confirming it floats — happens in Task 8, once the window exists to test against.)

## Task 5: `services/AiChat.qml` state singleton

**Files:**
- Create: `.config/quickshell/kessel/services/AiChat.qml`

**Interfaces:**
- Consumes: nothing from other QML tasks (Task 2's CLI contract is consumed here via `Process`/`SplitParser`, not a QML interface).
- Produces, for Task 6 (IPC) and Task 8 (window UI) to bind against:
  - `property bool shown`
  - `property string provider` (`"ollama"` | `"anthropic"` | `"openai"`), `property string model`
  - `property var messages` (array of `{role, content, html, provider, ts}`; `html` is `""` until Task 8's re-render call fills it in)
  - `property bool streaming`
  - `function toggle()`, `function open()`, `function close()`
  - `function send(text: string)` — appends a user message, spawns `ai-chat.py` in provider mode via a `Process`/`SplitParser`, appends/updates the trailing assistant message's `content` as `{"delta"}` lines arrive, then spawns `ai-chat.py --render` once `{"done"}` arrives and fills in that message's `html`
  - `function loadHistory()` / `function saveHistory()` against `~/.local/state/kessel/ai/history.json`

- [ ] **Step 1: Implement the singleton**

SPDX header, `pragma Singleton`, following `IslandState.qml`'s shape (plain `Singleton { id: root ... }`, no test framework in this repo — this is a state/IO file, verified by exercise in Task 6/8, not standalone). `send()`'s `Process` uses `stdin.text: JSON.stringify(root.messages.map(m => ({role: m.role, content: m.content})))` (sent once at spawn) and `stdout: SplitParser { onRead: data => { const chunk = JSON.parse(data); ... } }` for live line-by-line reads — `SplitParser` (not `StdioCollector`, which buffers until the process exits and would defeat the whole point of streaming) is new to this codebase; it's a real Quickshell.Io component (confirmed present in this Quickshell version's qmltypes). On `{"error": ...}`, set that as the assistant message's `content` and stop (`streaming = false`), don't spawn the render step. `loadHistory()` reads the JSON file at `Component.onCompleted` (via a `FileView`, matching `Board.qml`'s pattern) into `messages`; `saveHistory()` writes it back after every completed exchange.

- [ ] **Step 2: Reload and check for errors**

Run: `~/.config/hypr/scripts/island.sh restart && sleep 2 && qs log -c kessel | grep -E 'WARN|ERROR|caused'`
Expected: no new warnings/errors (the singleton isn't referenced by anything yet, so this mainly checks it parses — full exercise happens once Task 6/8 wire it up).

- [ ] **Step 3: Commit**

```bash
git add .config/quickshell/kessel/services/AiChat.qml
git commit -m "ai-chat: AiChat.qml state singleton (messages, streaming, history, provider calls)"
```

## Task 6: IPC wiring + keybind

**Files:**
- Modify: `.config/quickshell/kessel/services/IslandState.qml`
- Modify: `.config/hypr/keybinds.lua`

**Interfaces:**
- Consumes: `AiChat.toggle()`, `AiChat.open()`, `AiChat.close()` from Task 5.
- Produces: `qs -c kessel ipc call island aiChatToggle` works from a shell; `SUPER + I` runs it.

- [ ] **Step 1: Add the three functions to `IslandState.qml`'s existing `IpcHandler`**

```qml
function aiChatToggle(): string { AiChat.toggle(); return AiChat.shown ? "shown" : "hidden" }
function aiChatOpen(): string { AiChat.open(); return "ok" }
function aiChatClose(): string { AiChat.close(); return "ok" }
```

(Alongside the existing `timer`, `dnd`, etc. functions in that same handler, per `AGENTS.md`'s convention cited in the spec.)

- [ ] **Step 2: Add the keybind**

In `keybinds.lua`, alongside the other `island(...)` binds: `add { group = "Island", keys = "SUPER + I", exec = island("aiChatToggle"), desc = "AI chat" }` — no fallback argument, per the spec's deliberate exception.

- [ ] **Step 3: Regenerate shortcuts doc**

Run: `scripts/gen-shortcuts.sh`

- [ ] **Step 4: Verify config and reload**

Run: `KESSEL_STRICT=1 Hyprland --verify-config -c ~/.config/hypr/hyprland.lua && ~/.config/hypr/scripts/island.sh restart`
Expected: `config ok`, clean reload.

- [ ] **Step 5: Exercise the IPC directly**

Run: `qs -c kessel ipc call island aiChatToggle`
Expected: `shown` (Task 8 hasn't built the window yet, so nothing visible happens — this only proves the IPC path and the singleton's `shown` toggle work).

- [ ] **Step 6: Commit**

```bash
git add .config/quickshell/kessel/services/IslandState.qml .config/hypr/keybinds.lua docs/SHORTCUTS.md
git commit -m "ai-chat: wire SUPER+I through the existing island IPC handler"
```

## Task 7: `ui/AiChatWindow.qml` — the floating window shell

**Files:**
- Create: `.config/quickshell/kessel/ui/AiChatWindow.qml`
- Modify: `.config/quickshell/kessel/shell.qml`

**Interfaces:**
- Consumes: everything from `AiChat` (Task 5): `shown`, `messages`, `streaming`, `send()`.
- Produces: the window itself — Task 9 adds the settings view as a child of this window, not a separate top-level item.

- [ ] **Step 1: Implement the window**

SPDX header. Top-level `QtQuick.Window` (not `PanelWindow`), `title: "Kessel AI Chat"` (must match Task 4's rule exactly), `visible: AiChat.shown`, reasonable default `width`/`height` (e.g. 480×640) with `minimumWidth`/`minimumHeight` set so it's usably resizable. Background `Theme.island`, corners `Theme.radiusPanel`, border `Theme.borderWidth` — per the spec's "same family as the island" call. Contents: a `ListView` over `AiChat.messages`, each delegate a card (`Theme.card`/`Theme.cardHi`, `Theme.radiusCard`) containing a `TextArea { readOnly: true; wrapMode: Text.Wrap; textFormat: Text.RichText; text: modelData.html || modelData.content }` (falls back to plain content while streaming, before `html` is filled in) plus a small toolbar (copy button using existing `IconButton`/`Glyph` components, a quote-into-input button); below the list, a `SearchField`-styled input row with a send button, disabled while `AiChat.streaming`. A gear `IconButton` in the window's own header opens the settings view (Task 9 wires this).

- [ ] **Step 2: Instantiate it lazily from `shell.qml`**

```qml
LazyLoader {
    active: AiChat.shown
    AiChatWindow {}
}
```

(Matches `kessel-lock/shell.qml`'s `LazyLoader { active: ... }` pattern cited in the spec — constructed on first `SUPER + I`, not at shell startup.)

- [ ] **Step 3: Reload and check for errors**

Run: `~/.config/hypr/scripts/island.sh restart && sleep 2 && qs log -c kessel | grep -E 'WARN|ERROR|caused'`
Expected: clean.

- [ ] **Step 4: Exercise it for real**

Run: `qs -c kessel ipc call island aiChatToggle`, then `hyprctl clients -j | python3 -c "import json,sys; [print(c['class'],c['floating'],c['title']) for c in json.load(sys.stdin) if 'AI Chat' in c.get('title','')]"`
Expected: the window appears in the client list with `floating: true` (confirms Task 4's rule actually matched — this is the first point in the plan that can prove it, since the window didn't exist before). Take a screenshot (`grim -g "..."`) and look at it: does it look like the rest of kessel (dark, same corner radius/border weight as other panels), not a default-styled window?

- [ ] **Step 5: Commit**

```bash
git add .config/quickshell/kessel/ui/AiChatWindow.qml .config/quickshell/kessel/shell.qml
git commit -m "ai-chat: floating chat window, lazily loaded"
```

## Task 8: Sending a message end-to-end (streaming + render swap)

**Files:**
- Modify: `.config/quickshell/kessel/services/AiChat.qml` (fill in `send()`'s `Process` wiring if Task 5 left it stubbed; this task is where it's actually exercised)
- Modify: `.config/quickshell/kessel/ui/AiChatWindow.qml` (wire the input's send button/Enter to `AiChat.send(text)`)

**Interfaces:**
- Consumes: Task 2's CLI contract exactly (`--provider`/`--model` streaming, `--render` mode), Task 5's `send()`.

- [ ] **Step 1: Wire the input to `AiChat.send()`**

Enter in the input field or the send button calls `AiChat.send(inputField.text)`, then clears the field.

- [ ] **Step 2: Exercise with Ollama, if installed on this machine**

Run: `~/.config/hypr/scripts/island.sh restart`, then `qs -c kessel ipc call island aiChatToggle`, set the window's provider to `ollama` with a locally-pulled model, type a short prompt, send it.
Expected: text appears incrementally (not all at once), then — once done — the message re-renders with any markdown formatting applied. Screenshot it. State explicitly if no local Ollama model is available on this machine rather than skipping this step silently.

- [ ] **Step 3: Exercise the no-key error path**

Switch the provider to `anthropic` (assuming no key stored yet) and send a message.
Expected: the error message from Task 2's `{"error": "No API key configured..."}` appears in the chat, the input re-enables (not stuck disabled from `streaming` never clearing).

- [ ] **Step 4: Check logs clean**

Run: `qs log -c kessel | grep -E 'WARN|ERROR|caused'`
Expected: nothing new from this exercise.

- [ ] **Step 5: Commit**

```bash
git add .config/quickshell/kessel/services/AiChat.qml .config/quickshell/kessel/ui/AiChatWindow.qml
git commit -m "ai-chat: wire message sending end-to-end (stream, then render)"
```

## Task 9: Message actions (copy / quote / reply) + history persistence

**Files:**
- Modify: `.config/quickshell/kessel/ui/AiChatWindow.qml`
- Modify: `.config/quickshell/kessel/services/AiChat.qml`

**Interfaces:**
- Consumes: `AiChat.messages`, `AiChat.saveHistory()`/`loadHistory()` from Task 5.
- Produces: nothing further downstream — this is a leaf feature.

- [ ] **Step 1: Copy**

Each message card's copy button calls `Quickshell.clipboardText = modelData.content` (the raw text, not the rendered HTML — matches what you'd want pasted elsewhere).

- [ ] **Step 2: Quote into input**

A "quote" button prefixes the input field's current text with `"> " + modelData.content.split("\n").map(l => "> " + l).join("\n") + "\n\n"` (or inserts at cursor — builder's call on exact placement, the quoting itself is the pinned behavior).

- [ ] **Step 3: History persists across close/reopen**

Confirm `AiChat.close()` does not clear `messages` (only `shown = false`); confirm `saveHistory()` runs after each completed exchange (already wired in Task 5/8 — this step is verifying it, not adding new code if Task 5 already did it correctly).

- [ ] **Step 4: Exercise**

Send a message, close the window (`aiChatClose`), reopen (`aiChatToggle`).
Expected: prior messages still present. Check `~/.local/state/kessel/ai/history.json` directly (`cat` it) — contains the conversation, no API key or secret-looking value in it.

- [ ] **Step 5: Commit**

```bash
git add .config/quickshell/kessel/ui/AiChatWindow.qml .config/quickshell/kessel/services/AiChat.qml
git commit -m "ai-chat: copy/quote message actions, confirm history persistence"
```

## Task 10: In-window settings (provider/model picker, API key entry)

**Files:**
- Create: `.config/quickshell/kessel/ui/AiChatSettings.qml`
- Modify: `.config/quickshell/kessel/ui/AiChatWindow.qml` (gear button shows this as an inline view, not a separate window — per the spec's placement decision)

**Interfaces:**
- Consumes: `AiChat.provider`/`AiChat.model` (Task 5) to read/write the active selection.
- Produces: calls `ai-chat.py --store-key <provider>` / `--delete-key <provider>` (Task 3) via `Quickshell.Io.Process` with the key piped via `stdin.text`, never as an argv element — mirrors Task 3's own non-negotiable constraint, enforced here at the QML call site too.

- [ ] **Step 1: Implement the settings view**

SPDX header. A provider list (Ollama, Anthropic, OpenAI) each with: a model name field (plain text — free-form, since available models vary and aren't enumerated by this plan), and for Anthropic/OpenAI, a password-masked key input + "Save"/"Clear" buttons. "Save" spawns `ai-chat.py --store-key <provider>` with `stdin.text: keyField.text` and clears the field from memory immediately after the `Process` starts (`keyField.text = ""`) — the field is not readable after submission even if nothing stores it anywhere this repo tracks. Uses `Theme.*`/existing `components/*` throughout, per the dots-aesthetic note.

- [ ] **Step 2: Wire the gear button**

`AiChatWindow.qml`'s header gear `IconButton` toggles a `showSettings` boolean that swaps the message list for `AiChatSettings.qml` in place (not a new window).

- [ ] **Step 3: Reload and exercise**

Run: `~/.config/hypr/scripts/island.sh restart`, open the chat window, open settings, store a fake key for `anthropic`, verify via `secret-tool lookup service kessel-ai provider anthropic` that it landed, clear it via the UI, verify the lookup now fails.

- [ ] **Step 4: Check logs clean and no secret leakage**

Run: `qs log -c kessel | grep -E 'WARN|ERROR|caused'`, and separately confirm the stored key value doesn't appear anywhere in that log output or in `~/.local/state/kessel/ai/history.json`.

- [ ] **Step 5: Commit**

```bash
git add .config/quickshell/kessel/ui/AiChatSettings.qml .config/quickshell/kessel/ui/AiChatWindow.qml
git commit -m "ai-chat: in-window settings (provider/model, API key store/clear)"
```

## Task 11: Final end-to-end pass

**Files:** none (verification only)

- [ ] **Step 1: Full validation suite**

Run every command in `AGENTS.md`'s "How to validate" section (`KESSEL_STRICT=1 Hyprland --verify-config`, `scripts/gen-shortcuts.sh`, `bash -n` across `scripts/*.sh scripts/desktop/*.sh`, `./install.sh --dry-run --with-aur --apply-config` must change nothing, `./install.sh --check`), plus `cd scripts/desktop && python3 -m pytest test_ai_chat.py -v` (all tests from Tasks 1–3).

- [ ] **Step 2: Full manual exercise, screenshot at each stage**

`SUPER + I` opens the window (floating, not tiled — confirm via `hyprctl clients`); send a message with a code block and a math expression to Ollama (if available) and confirm live streaming then a re-rendered, syntax-highlighted, math-typeset result; copy a message; quote a message; close and reopen, history intact; open settings, store and clear a fake key.

- [ ] **Step 3: Update `docs/backlog/ai-chat.md` and close issue #2**

Mark the backlog doc as shipped (keep it, don't delete — matches this repo's own convention of keeping backlog docs as a historical record). `gh issue close 2 --repo velitchko/dots --comment "Shipped — see docs/superpowers/specs/2026-11-09-ai-chat-panel-design.md and the commits on main."`

- [ ] **Step 4: Commit**

```bash
git add docs/backlog/ai-chat.md
git commit -m "ai-chat: mark backlog item shipped"
```
