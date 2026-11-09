# SPDX-License-Identifier: GPL-3.0-or-later
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
    # pygments wraps each token in its own <span>, so the escaped characters
    # aren't contiguous text -- check they're present, not stitched together.
    assert "&lt;" in html and "&gt;" in html


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
    html = render_markdown("```python\ndef f():\n    pass\n<script>x</script>", math_dir=str(tmp_path))
    assert "<script>x" not in html  # must not raise, AND must still come out escaped


def test_stray_backtick_does_not_leak_raw_html_across_paragraphs(tmp_path):
    # a single unmatched backtick used to make CODE_FENCE_RE's `[^`]*` (DOTALL)
    # "stash" everything up to the next backtick -- including unrelated later
    # paragraphs -- as code, skipping escaping for all of it. Real markdown
    # inline code never spans a blank line (paragraph break); matching that.
    html = render_markdown(
        "Use the `key.\n\n<img src=\"http://attacker.example/x.png\">\n\n"
        "<a href=\"x\">and</a>` again",
        math_dir=str(tmp_path),
    )
    # the URL/tag text is fine to show as inert escaped text (the user did
    # type it); what must never happen is a *live* tag.
    assert "<img" not in html
    assert "<a " not in html
    assert "&lt;img" in html and "&lt;a" in html


def test_remote_image_single_quoted_attr_is_stripped(tmp_path):
    # a regex allowlist that only matches `src="..."` (double-quoted) is a
    # parser differential: markdown's own output happens to always double-
    # quote, but asserting that is fragile. Prove the filter is a real
    # parser, not a regex, by feeding it formatting a regex would miss.
    html = render_markdown("![x](http://attacker.example/x.png 'title')", math_dir=str(tmp_path))
    assert "attacker.example" not in html


def test_blockquote_is_not_double_escaped(tmp_path):
    html = render_markdown("> a quoted line", math_dir=str(tmp_path))
    assert "<blockquote>" in html
    assert "&gt; a quoted" not in html


def test_autolink_renders_as_real_link(tmp_path):
    html = render_markdown("<https://example.com>", math_dir=str(tmp_path))
    assert '<a href="https://example.com">' in html


def test_table_renders_with_visible_borders(tmp_path):
    html = render_markdown("| a | b |\n|---|---|\n| 1 | 2 |", math_dir=str(tmp_path))
    assert "border" in html


import json
import subprocess
import sys


def run_cli(args, stdin_text):
    return subprocess.run([sys.executable, "ai_chat.py", *args], input=stdin_text,
                           capture_output=True, text=True)


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


def test_remote_image_markdown_syntax_is_stripped(tmp_path):
    # ![alt](url) is core markdown syntax -- python-markdown turns it into a
    # real <img> tag during md.convert(), *after* the prose-escaping pass, so
    # html.escape() never sees it. Qt's Text.RichText auto-fetches <img src>
    # on render with no user interaction: an attacker-controlled URL in a
    # model's own response would silently exfiltrate to that URL (a tracking
    # pixel), violating "no network call the user hasn't configured".
    html = render_markdown("![leak](http://attacker.example/track.png?x=1)", math_dir=str(tmp_path))
    assert "attacker.example" not in html
    assert "<img" not in html


def test_own_math_image_is_not_stripped(tmp_path):
    # the allowlist must still let through the one <img> source this module
    # itself generates: a file:// path under the given math_dir.
    html = render_markdown("Math: $E = mc^2$", math_dir=str(tmp_path))
    assert f'<img src="file://{tmp_path}' in html


def test_javascript_link_href_is_neutralized(tmp_path):
    html = render_markdown("[click me](javascript:alert(1))", math_dir=str(tmp_path))
    assert "javascript:" not in html


def test_safe_stream_catches_mid_stream_exception():
    # a dropped connection, a malformed JSON line, anything -- must end the
    # stream with a final error chunk, not raise out of main() and leave
    # the QML side's `streaming` flag (and disabled input) stuck forever.
    import ai_chat

    def flaky():
        yield {"delta": "partial"}
        raise ConnectionError("boom")

    chunks = list(ai_chat._safe_stream(flaky()))
    assert chunks[0] == {"delta": "partial"}
    assert "error" in chunks[-1]


def test_ollama_in_stream_error_is_surfaced(monkeypatch):
    import ai_chat, requests as req

    class FakeResponse:
        status_code = 200
        def iter_lines(self, decode_unicode=False):
            yield '{"error": "model requires more system memory"}'

    monkeypatch.setattr(req, "post", lambda *a, **k: FakeResponse())
    chunks = list(ai_chat.stream_ollama(model="x", messages=[]))
    assert any("error" in c for c in chunks)


def test_anthropic_sse_error_event_is_surfaced(monkeypatch):
    import ai_chat, requests as req
    monkeypatch.setattr(ai_chat, "get_key", lambda p: "fake-key")

    class FakeResponse:
        status_code = 200
        def iter_lines(self, decode_unicode=False):
            yield 'data: {"type": "error", "error": {"message": "overloaded_error"}}'

    monkeypatch.setattr(req, "post", lambda *a, **k: FakeResponse())
    chunks = list(ai_chat.stream_anthropic(model="x", messages=[]))
    assert any("error" in c for c in chunks)


def test_requests_have_a_timeout(monkeypatch):
    import ai_chat, requests as req
    captured = []

    class FakeResponse:
        status_code = 200
        def iter_lines(self, decode_unicode=False):
            return iter([])

    def fake_post(*a, **k):
        captured.append(k)
        return FakeResponse()

    monkeypatch.setattr(req, "post", fake_post)
    monkeypatch.setattr(ai_chat, "get_key", lambda p: "fake-key")
    list(ai_chat.stream_ollama(model="x", messages=[]))
    list(ai_chat.stream_anthropic(model="x", messages=[]))
    list(ai_chat.stream_openai_compatible(model="x", messages=[], base_url="http://x"))
    assert captured and all("timeout" in k for k in captured)


def test_openai_compatible_hits_custom_url_without_requiring_a_key(monkeypatch):
    import ai_chat, requests as req

    class FakeResponse:
        status_code = 200
        def iter_lines(self, decode_unicode=False):
            yield 'data: {"choices":[{"delta":{"content":"hi"}}]}'
            yield 'data: [DONE]'

    captured = {}
    def fake_post(url, **kwargs):
        captured["url"] = url
        captured["headers"] = kwargs.get("headers", {})
        return FakeResponse()

    monkeypatch.setattr(req, "post", fake_post)
    monkeypatch.setattr(ai_chat, "get_key", lambda provider: None)
    chunks = list(ai_chat.stream_openai_compatible(
        model="local-model",
        messages=[{"role": "user", "content": "hi"}],
        base_url="http://localhost:8080/v1/chat/completions",
    ))
    assert captured["url"] == "http://localhost:8080/v1/chat/completions"
    assert "Authorization" not in captured["headers"]
    assert any(c.get("delta") == "hi" for c in chunks)
