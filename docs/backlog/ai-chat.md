# AI chat panel

> Tracked as issue #2 in this repo's tracker.

**Type:** feature · **Priority:** maybe later

A floating/hovering chat window, opened with a dedicated keybind (candidate: `SUPER + I`), separate from the island's own panels — it can stay open and move independently while you work, not tied to the pill's morph animation.

- **Rich rendering:** markdown (code blocks with syntax highlighting, tables, lists) and LaTeX/math rendering in responses, not just plain text
- **Message interaction:** copy a message or a selection, quote a message into a reply, respond inline
- **Providers, plug-in style:** bring your own API key (Anthropic, OpenAI, others) stored in the system keyring, never in the repo
- **Subscriptions:** use an existing Claude or ChatGPT subscription instead of per-token API billing, where that's actually possible — **under investigation**, since this depends on what each provider actually permits a third-party app to do; may end up Claude-only, or not make it in at all if there's no legitimate path
- **Local / self-hosted models:** Ollama (official repo) as the local backend; support a self-hosted/remote OpenAI-compatible endpoint too
- Off by default. No network traffic unless a provider is explicitly configured.
- Short history kept in `~/.local/state/kessel/ai/`

**Resolved:** this is a standalone panel, not folded into the launcher's input.

**Open questions:** which local models are realistic on a laptop without a GPU; exact keybind; how far the subscription-auth path can legitimately go per-provider (see investigation above).
