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
from html.parser import HTMLParser
import markdown
import requests

MATH_INLINE_RE = re.compile(r"\$\$(.+?)\$\$|\$([^\s$](?:[^$\n]*[^\s$])?)\$", re.DOTALL)
# Triple-backtick fences legitimately span multiple lines (DOTALL); a single
# backtick span must not -- real markdown inline code never crosses a blank
# line, and allowing it here once let an unmatched stray backtick "stash"
# everything up to the next backtick, including unrelated later paragraphs,
# out of the math-protection pass (see render_markdown's docstring for why
# that stopped being a security issue but was still a correctness one).
CODE_FENCE_RE = re.compile(r"```.*?```|`[^`\n]*`", re.DOTALL)


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
    """Replace fenced/inline code spans with NUL placeholders so math
    extraction doesn't treat a literal '$' inside code as a math delimiter.
    (Escaping is no longer this function's concern -- see render_markdown.)
    Returns (stashed_text, spans)."""
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


class _Sanitizer(HTMLParser):
    """Real HTML parsing, not regex, so a quoting/casing variation a regex
    wouldn't anticipate (single-quoted attrs, upper-case tags, no quotes at
    all) can't slip past -- a regex allowlist only has to agree with
    whichever formatting it was written against, which is exactly the
    "parser differential" class of sanitizer bypass.

    - <img>: only a src that is this module's own file://<math_dir> path
      survives, by prefix match on the *parsed* attribute value. Markdown's
      native ![alt](url) syntax turns into a real <img src="..."> during
      md.convert(), and Qt's Text.RichText auto-fetches an <img src> on
      render with no user interaction -- a model's own response could
      otherwise embed a tracking-pixel URL and silently exfiltrate to it.
    - <a>: only an http(s) href stays live; anything else (javascript:,
      data:, file:, ...) is defanged to "#".
    - every other tag/attribute is re-emitted as parsed (re-escaped), since
      by this point the only tags in play are ones this module's own
      markdown.Markdown instance generated (codehilite's styled <span>s,
      <table>, headings, ...), not attacker-authored markup.
    """

    VOID_TAGS = {"img", "br", "hr", "input", "meta", "link"}

    def __init__(self, math_dir):
        super().__init__(convert_charrefs=True)
        self.safe_img_prefix = "file://" + math_dir
        self.out = []

    def _emit_tag(self, tag, attrs, self_closing):
        attrs = dict(attrs)
        if tag == "img":
            src = attrs.get("src") or ""
            if not src.startswith(self.safe_img_prefix):
                return
            attrs = {"src": src, "style": attrs.get("style", "")}
        elif tag == "a":
            href = attrs.get("href") or ""
            if not (href.startswith("http://") or href.startswith("https://")):
                attrs["href"] = "#"
        attr_str = "".join(f' {k}="{html.escape(v or "", quote=True)}"' for k, v in attrs.items())
        self.out.append(f"<{tag}{attr_str}{'/' if self_closing else ''}>")

    def handle_starttag(self, tag, attrs):
        self._emit_tag(tag, attrs, self_closing=tag in self.VOID_TAGS)

    def handle_startendtag(self, tag, attrs):
        self._emit_tag(tag, attrs, self_closing=True)

    def handle_endtag(self, tag):
        if tag not in self.VOID_TAGS:
            self.out.append(f"</{tag}>")

    def handle_data(self, data):
        self.out.append(html.escape(data))

    def get_html(self):
        return "".join(self.out)


def _sanitize_html(rendered_html, math_dir):
    parser = _Sanitizer(math_dir)
    parser.feed(rendered_html)
    parser.close()
    return parser.get_html()


def render_markdown(text, *, text_color="#e8e8e8", math_dir):
    """Convert a model response to Qt Text.RichText-safe HTML: markdown,
    pygments-highlighted fenced code, and matplotlib-rendered math images.

    Raw HTML handling is disabled in the markdown instance itself (not
    pre-escaped by hand): python-markdown passes raw HTML straight through
    by default, per the original Markdown spec, which would let a model's
    response inject markup -- but hand-escaping first (an earlier version
    of this function did) also breaks legitimate markdown that happens to
    use angle brackets (blockquotes' own rendering, autolinks) and, worse,
    is only as good as the code-span regex protecting it: a stray unmatched
    backtick could "stash" an unrelated later paragraph as code and skip
    the escaping pass entirely. Disabling raw HTML at the source means
    every angle bracket in the model's text is just text, unconditionally,
    regardless of where it falls.

    The one thing markdown *can* still produce that reaches out to the
    network is its own native ![alt](url) image syntax -- real HTML, not
    something "raw HTML disabled" suppresses, since the <img> tag comes
    from markdown's own renderer, not from the input text. _sanitize_html
    is a real HTML parser (not regex) allowlist pass for exactly that.
    """
    stashed, code_spans = _stash_code(text)
    stashed, math_html = _extract_math(stashed, text_color, math_dir)
    with_code = _restore_code(stashed, code_spans)

    md = markdown.Markdown(
        extensions=["fenced_code", "codehilite", "tables"],
        extension_configs={"codehilite": {"noclasses": True, "pygments_style": "monokai"}},
    )
    md.preprocessors.deregister("html_block")
    md.inlinePatterns.deregister("html")
    rendered = md.convert(with_code)
    rendered = _sanitize_html(rendered, math_dir)

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
