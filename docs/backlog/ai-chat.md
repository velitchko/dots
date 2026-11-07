# AI chat panel (optional)

> Tracked as issue #2 in this repo's tracker.

**Type:** feature · **Priority:** maybe later

An optional assistant panel, closer to a small utility than a new desktop centrepiece. Ask from the launcher (for example, `?? how do I…`) or a dedicated binding; answers stream into the island.

- **Local first:** Ollama (official repo) as the default backend; remote APIs strictly opt-in with the key stored in the system keyring (never in the repo)
- Copy / insert answer, keep a short history in `~/.local/state/kessel/ai/`
- Off by default. No network traffic unless it is explicitly configured.

**Open questions:** which models fit a laptop without a GPU; whether to share the launcher's input or have a separate panel.
