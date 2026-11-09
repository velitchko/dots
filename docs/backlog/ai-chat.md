# AI chat panel

> Tracked as issue #2 in this repo's tracker. **Shipped** — see
> `docs/superpowers/specs/2026-11-09-ai-chat-panel-design.md` and the
> commits on `main` from that date. Kept here as a record of the original
> ask and the decisions made building it, not as an open item.

**Type:** feature · **Priority:** maybe later

A floating/hovering chat window, opened with a dedicated keybind (candidate: `SUPER + I`), separate from the island's own panels — it can stay open and move independently while you work, not tied to the pill's morph animation.

- **Rich rendering:** markdown (code blocks with syntax highlighting, tables, lists) and LaTeX/math rendering in responses, not just plain text
- **Message interaction:** copy a message or a selection, quote a message into a reply, respond inline
- **Providers, plug-in style:** bring your own API key (Anthropic, OpenAI, others) stored in the system keyring, never in the repo
- **Subscriptions: not feasible, investigated and closed.** Anthropic's Claude Code legal docs explicitly prohibit third-party apps from offering Claude.ai login or routing requests through Free/Pro/Max/Ultra plan credentials — a stated policy, not just a missing integration. OpenAI's "Sign in with ChatGPT" plan-usage program is partner-only (waitlist), not open to a personal tool. API keys only.
- **Local / self-hosted models:** Ollama (official repo) as the local backend; support a self-hosted/remote OpenAI-compatible endpoint too
- Off by default. No network traffic unless a provider is explicitly configured.
- Short history kept in `~/.local/state/kessel/ai/`

**Resolved:** this is a standalone panel, not folded into the launcher's input. Subscription auth is out of scope (see above) — API keys + local/self-hosted models only. Keybind: `SUPER + I`. Syntax-highlighted code and real LaTeX math both shipped (server-side, via python-markdown/pygments/matplotlib — no browser engine; a `WebEngineView` spike crashed Quickshell outright, see the design doc).

**Open questions, as of shipping:** which local models are realistic on a laptop without a GPU is still genuinely open — tested against `qwen2.5:0.5b` only.

**Follow-up polish (same day):** user avatar (`~/.face`) + username on your own messages, a robot glyph + "ai (model)" on replies; auto-titled sessions and a less generic empty-state title ("Intelligence"); a bigger default window size; a per-reply system prompt (global, editable in Settings) with a default Arch/bash/fish persona; a thinking indicator (three pulsing dots) for the gap before the first token. Answered the local-model question above: `qwen2.5-coder:3b` gave clearly better answers than `qwen2.5:0.5b` in a side-by-side test (correctly honored "assume fish" from the system prompt, more coherent reasoning) and is the new default; `qwen2.5-coder:1.5b` is a faster but noticeably less reliable fallback. Also fixed a real bug, not just polish: streaming used to reassign the whole message array per token, which reset the message list's scroll position every single token (confirmed on screen recording) — streamed text now accumulates separately so the array only changes twice per reply.
