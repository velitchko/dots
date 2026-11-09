# SPDX-License-Identifier: GPL-3.0-or-later
"""ai_chat.py — AI chat panel backend: markdown/math rendering and (later
tasks) provider streaming + secret storage. Spawned by services/AiChat.qml;
see docs/superpowers/specs/2026-11-09-ai-chat-panel-design.md.
"""
import argparse
import hashlib
import html
import json
import os
import re
import subprocess
import sys
import markdown
import requests

MATH_INLINE_RE = re.compile(r"\$\$(.+?)\$\$|\$([^\s$](?:[^$\n]*[^\s$])?)\$", re.DOTALL)
CODE_FENCE_RE = re.compile(r"```.*?```|`[^`]*`", re.DOTALL)


def _render_math_png(expr, text_color, math_dir):
    """Render one math expression to a transparent PNG under math_dir.
    Returns the file path, or None if the expression doesn't typeset."""
    import matplotlib
    matplotlib.use("agg")
    import matplotlib.pyplot as plt

    os.makedirs(math_dir, exist_ok=True)
    digest = hashlib.sha256(f"{expr}|{text_color}".encode()).hexdigest()[:16]
    path = os.path.join(math_dir, f"math-{digest}.png")
    if os.path.isfile(path):
        return path

    fig = plt.figure(figsize=(0.01, 0.01))
    try:
        fig.text(0, 0, f"${expr}$", fontsize=16, color=text_color)
        fig.savefig(path, transparent=True, bbox_inches="tight", pad_inches=0.05, dpi=150)
        return path
    except Exception:
        return None
    finally:
        plt.close(fig)


def _stash_code(text):
    """Replace fenced/inline code spans with NUL placeholders so the rest of
    the pipeline (math extraction, HTML escaping) can treat the remainder as
    plain prose without disturbing code content. Returns (stashed_text, spans)."""
    spans = []

    def stash(m):
        spans.append(m.group(0))
        return f"\x00CODE{len(spans) - 1}\x00"

    return CODE_FENCE_RE.sub(stash, text), spans


def _restore_code(text, spans):
    for i, code in enumerate(spans):
        text = text.replace(f"\x00CODE{i}\x00", code)
    return text


def _extract_math(prose_text, text_color, math_dir):
    """Replace $...$/$$...$$ math spans in already-code-protected prose text
    with placeholders, returning (text_with_placeholders, {placeholder: html}).
    Only called on text with code already stashed out -- '$' inside code is
    literal, never math."""
    placeholders = {}

    def replace_math(m):
        expr = m.group(1) if m.group(1) is not None else m.group(2)
        # A bare "$42 and $7" greedily matches as one span (content "42 and")
        # with no way to tell, from delimiters alone, that it's two prices,
        # not one expression. Require at least one real math marker in the
        # content -- true math almost always has one ("E = mc^2", "x_1",
        # "\sum"); plain prose caught between two currency amounts won't.
        if not re.search(r"[=^_\\{}+*/<>]", expr):
            return m.group(0)  # leave the original text untouched
        path = _render_math_png(expr, text_color, math_dir)
        if path is None:
            return m.group(0)
        key = f"\x00MATH{len(placeholders)}\x00"
        placeholders[key] = f'<img src="file://{path}" style="vertical-align:middle">'
        return key

    return MATH_INLINE_RE.sub(replace_math, prose_text), placeholders


def _strip_unsafe_images(rendered_html, math_dir):
    """Only let through <img> tags this module itself generated (a file://
    path under math_dir). Markdown's native ![alt](url) syntax turns into a
    real <img src="..."> during md.convert() -- *after* the prose-escaping
    pass below, so html.escape() never sees it -- and Qt's Text.RichText
    auto-fetches an <img src> on render with no user interaction. A model's
    own response (remote API or a message that echoes back untrusted text)
    could otherwise embed a tracking-pixel URL and silently exfiltrate to
    it, violating "no network call the user hasn't configured"."""
    safe_prefix = "file://" + math_dir

    def strip(m):
        return m.group(0) if m.group(1).startswith(safe_prefix) else ""

    return re.sub(r'<img\b[^>]*\bsrc="([^"]*)"[^>]*/?>', strip, rendered_html)


def _neutralize_unsafe_links(rendered_html):
    """Only http(s) link targets stay clickable; javascript:/data:/file:/
    other schemes get their href dropped rather than left live."""
    def neutralize(m):
        href = m.group(1)
        if href.startswith("http://") or href.startswith("https://"):
            return m.group(0)
        return m.group(0).replace(f'href="{href}"', 'href="#"')

    return re.sub(r'<a\b[^>]*\bhref="([^"]*)"[^>]*>', neutralize, rendered_html)


def render_markdown(text, *, text_color="#e8e8e8", math_dir):
    """Convert a model response to Qt Text.RichText-safe HTML: markdown,
    pygments-highlighted fenced code, and matplotlib-rendered math images.

    Code fence content is left untouched for markdown/codehilite to escape
    and highlight itself (it already does this correctly); raw HTML in prose
    is explicitly escaped here first, since python-markdown's default
    behaviour -- passing raw HTML straight through, per the original
    Markdown spec -- would otherwise let a model's response inject markup.
    """
    stashed, code_spans = _stash_code(text)
    stashed, math_html = _extract_math(stashed, text_color, math_dir)
    escaped_prose = html.escape(stashed)
    # html.escape() also escapes the NUL-byte placeholder markers' literal
    # text content is unaffected (they contain no &/</>), so this is safe.
    with_code = _restore_code(escaped_prose, code_spans)

    md = markdown.Markdown(
        extensions=["fenced_code", "codehilite", "tables"],
        extension_configs={"codehilite": {"noclasses": True, "pygments_style": "monokai"}},
    )
    rendered = md.convert(with_code)
    rendered = _strip_unsafe_images(rendered, math_dir)
    rendered = _neutralize_unsafe_links(rendered)

    for key, img_html in math_html.items():
        rendered = rendered.replace(key, img_html)

    # Qt's rich-text engine doesn't render the bare `border` HTML attribute;
    # give tables/cells an explicit inline style instead.
    rendered = rendered.replace("<table>", '<table style="border-collapse:collapse;border:1px solid #555">')
    rendered = re.sub(r"<(td|th)>", r'<\1 style="border:1px solid #555;padding:4px">', rendered)

    return rendered


def get_key(provider):
    """Look up a provider's API key from the system keyring. None means "not
    configured yet" (expected state, not an error) — never raises for that."""
    result = subprocess.run(
        ["secret-tool", "lookup", "service", "kessel-ai", "provider", provider],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def store_key(provider, key):
    """Admin action, not part of the chat loop: the secret is passed via
    stdin, never as a subprocess argv element, so it never appears in a
    `ps aux` listing."""
    subprocess.run(
        ["secret-tool", "store", "--label", f"kessel-ai-{provider}",
         "service", "kessel-ai", "provider", provider],
        input=key, text=True,
    )


def delete_key(provider):
    subprocess.run(["secret-tool", "clear", "service", "kessel-ai", "provider", provider])


def render_mode(text):
    """ai-chat.py --render: render a single complete message's raw text."""
    math_dir = os.path.expanduser("~/.local/state/kessel/ai/math/")
    os.makedirs(math_dir, exist_ok=True)
    return json.dumps({"html": render_markdown(text, math_dir=math_dir)})


def stream_ollama(*, model, messages):
    try:
        response = requests.post(
            "http://localhost:11434/api/chat",
            json={"model": model, "messages": messages, "stream": True},
            stream=True,
        )
    except requests.ConnectionError:
        yield {"error": "Ollama isn't running (localhost:11434)"}
        return
    if response.status_code != 200:
        yield {"error": f"Ollama error ({response.status_code}): {response.text[:200]}"}
        return
    for line in response.iter_lines(decode_unicode=True):
        if not line:
            continue
        obj = json.loads(line)
        content = obj.get("message", {}).get("content", "")
        if content:
            yield {"delta": content}
        if obj.get("done"):
            yield {"done": True}
            return


def stream_anthropic(*, model, messages):
    key = get_key("anthropic")
    if key is None:
        yield {"error": "No API key configured for anthropic — add one in Settings"}
        return
    try:
        response = requests.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            json={"model": model, "max_tokens": 4096, "messages": messages, "stream": True},
            stream=True,
        )
    except requests.ConnectionError:
        yield {"error": "Could not reach the Anthropic API"}
        return
    if response.status_code != 200:
        yield {"error": f"Anthropic API error ({response.status_code}): {response.text[:200]}"}
        return
    for line in response.iter_lines(decode_unicode=True):
        if not line or not line.startswith("data: "):
            continue
        obj = json.loads(line[len("data: "):])
        if obj.get("type") == "content_block_delta":
            text = obj.get("delta", {}).get("text", "")
            if text:
                yield {"delta": text}
        elif obj.get("type") == "message_stop":
            yield {"done": True}
            return
    yield {"done": True}


def stream_openai(*, model, messages, base_url="https://api.openai.com/v1/chat/completions", key_provider="openai", require_key=True):
    key = get_key(key_provider)
    if key is None and require_key:
        yield {"error": f"No API key configured for {key_provider} — add one in Settings"}
        return
    headers = {"content-type": "application/json"}
    if key:
        headers["Authorization"] = f"Bearer {key}"
    try:
        response = requests.post(base_url, headers=headers, json={"model": model, "messages": messages, "stream": True}, stream=True)
    except requests.ConnectionError:
        yield {"error": f"Could not reach {base_url}"}
        return
    if response.status_code != 200:
        yield {"error": f"API error ({response.status_code}): {response.text[:200]}"}
        return
    for line in response.iter_lines(decode_unicode=True):
        if not line or not line.startswith("data: "):
            continue
        payload = line[len("data: "):]
        if payload == "[DONE]":
            yield {"done": True}
            return
        obj = json.loads(payload)
        delta = (obj.get("choices") or [{}])[0].get("delta", {}).get("content")
        if delta:
            yield {"delta": delta}
    yield {"done": True}


def stream_openai_compatible(*, model, messages, base_url):
    """Self-hosted/local server speaking the OpenAI chat-completions format
    (llama.cpp, LM Studio, vLLM, text-generation-webui, ...). A key is
    optional -- most local servers don't check one -- not required."""
    yield from stream_openai(model=model, messages=messages, base_url=base_url, key_provider="openai-compatible", require_key=False)


PROVIDERS = {"ollama": stream_ollama, "anthropic": stream_anthropic, "openai": stream_openai, "openai-compatible": stream_openai_compatible}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", choices=sorted(PROVIDERS))
    parser.add_argument("--model")
    parser.add_argument("--base-url", help="required for --provider openai-compatible")
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--store-key", metavar="PROVIDER")
    parser.add_argument("--delete-key", metavar="PROVIDER")
    args = parser.parse_args()

    if args.render:
        print(render_mode(sys.stdin.read()))
        return

    if args.store_key:
        store_key(args.store_key, sys.stdin.readline().rstrip("\n"))
        return

    if args.delete_key:
        delete_key(args.delete_key)
        return

    if args.provider:
        messages = json.loads(sys.stdin.read())
        kwargs = {"model": args.model, "messages": messages}
        if args.provider == "openai-compatible":
            kwargs["base_url"] = args.base_url
        for chunk in PROVIDERS[args.provider](**kwargs):
            print(json.dumps(chunk), flush=True)
        return

    parser.error("one of --render, --store-key, --delete-key, or --provider/--model is required")


if __name__ == "__main__":
    main()
