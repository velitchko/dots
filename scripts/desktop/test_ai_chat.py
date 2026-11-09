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
    render_markdown("```python\ndef f():\n    pass", math_dir=str(tmp_path))  # must not raise


def test_table_renders_with_visible_borders(tmp_path):
    html = render_markdown("| a | b |\n|---|---|\n| 1 | 2 |", math_dir=str(tmp_path))
    assert "border" in html
