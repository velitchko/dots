# SPDX-License-Identifier: GPL-3.0-or-later
"""ai_chat.py — AI chat panel backend: markdown/math rendering and (later
tasks) provider streaming + secret storage. Spawned by services/AiChat.qml;
see docs/superpowers/specs/2026-11-09-ai-chat-panel-design.md.
"""
import hashlib
import html
import os
import re
import markdown

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

    for key, img_html in math_html.items():
        rendered = rendered.replace(key, img_html)

    # Qt's rich-text engine doesn't render the bare `border` HTML attribute;
    # give tables/cells an explicit inline style instead.
    rendered = rendered.replace("<table>", '<table style="border-collapse:collapse;border:1px solid #555">')
    rendered = re.sub(r"<(td|th)>", r'<\1 style="border:1px solid #555;padding:4px">', rendered)

    return rendered
