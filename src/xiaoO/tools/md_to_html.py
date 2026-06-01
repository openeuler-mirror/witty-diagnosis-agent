#!/usr/bin/env python3

import datetime as dt
import html
import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple


STYLE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{title}</title>
<style>
:root{{
  --bg:#ffffff;--surface:#ffffff;--border:#e5e7eb;--border-soft:#f3f4f6;
  --text:#1f2937;--text-2:#5b6472;--text-3:#99a1ab;
  --accent:#0f5f73;--accent-light:#e3f3f6;--accent-mid:#2f89a1;
  --red:#b42318;--red-bg:#fef3f2;--amber:#b54708;--amber-bg:#fff7ed;
  --green:#027a48;--green-bg:#ecfdf3;--code-bg:#17202a;--code-text:#d8e1ea;
  --code-border:#263343;--shadow:0 1px 3px rgba(15,23,42,.08),0 10px 28px rgba(15,23,42,.06);
  --radius:10px;--radius-lg:16px;--gap:32px;--toc-width:240px;
  --font-body:"Noto Sans SC","PingFang SC","Microsoft YaHei","Helvetica Neue",Arial,sans-serif;
  --font-head:"Noto Serif SC","Songti SC","STSong","Times New Roman",serif;
  --font-mono:"JetBrains Mono","SFMono-Regular","Cascadia Code","Fira Code",Consolas,monospace;
}}
*,*::before,*::after{{box-sizing:border-box}}
html{{font-size:16px;scroll-behavior:smooth}}
body{{margin:0;font-family:var(--font-body);line-height:1.8;color:var(--text);background:
  radial-gradient(circle at top left, rgba(15,95,115,.08), transparent 28%),
  radial-gradient(circle at top right, rgba(181,71,8,.08), transparent 24%),
  var(--bg);-webkit-font-smoothing:antialiased}}
#progress{{position:fixed;top:0;left:0;height:3px;width:0;background:linear-gradient(90deg,var(--accent-mid),var(--accent));z-index:999}}
.layout{{display:flex;gap:var(--gap);max-width:calc(var(--toc-width) + 840px + var(--gap) * 3);margin:0 auto;padding:44px var(--gap) 88px}}
.toc{{width:var(--toc-width);flex-shrink:0;position:sticky;top:28px;max-height:calc(100vh - 56px);overflow:auto;background:rgba(255,255,255,.88);backdrop-filter:blur(10px);border:1px solid var(--border);border-radius:var(--radius-lg);padding:18px;box-shadow:var(--shadow)}}
.toc-title{{font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--text-3);margin-bottom:12px;padding-bottom:10px;border-bottom:1px solid var(--border-soft)}}
.toc a{{display:block;padding:5px 8px;border-radius:7px;text-decoration:none;color:var(--text-2);font-size:13px;line-height:1.45;transition:background .15s ease,color .15s ease}}
.toc a:hover,.toc a.active{{background:var(--accent-light);color:var(--accent)}}
.toc-l1,.toc-l2{{font-weight:600;color:var(--text)}}
.toc-l3{{padding-left:16px!important;font-size:12px!important}}
.article{{flex:1;min-width:0;background:rgba(255,255,255,.92);backdrop-filter:blur(10px);border:1px solid var(--border);border-radius:24px;padding:52px 60px;box-shadow:var(--shadow)}}
.article h1{{margin:0 0 28px;padding-bottom:18px;border-bottom:2px solid var(--text);font-family:var(--font-head);font-size:28px;line-height:1.3}}
.article h2{{margin:48px 0 16px;padding-bottom:8px;border-bottom:1px solid var(--border);font-family:var(--font-head);font-size:20px;line-height:1.35}}
.article h2::before{{content:attr(data-index);display:inline-block;margin-right:10px;padding:1px 7px;border-radius:5px;background:var(--accent-light);color:var(--accent-mid);font-size:11px;font-family:var(--font-mono);letter-spacing:.05em;vertical-align:middle}}
.article h3{{margin:28px 0 10px;font-size:16px;font-family:var(--font-head)}}
.article h3::before{{content:"§ ";color:var(--text-3);font-family:var(--font-mono);font-size:13px}}
.article h4{{margin:20px 0 8px;color:var(--accent);font-size:14px}}
.article p,.plain{{margin:0 0 12px;font-size:15px}}
.article ul,.article ol{{margin:6px 0 14px;padding-left:22px}}
.article li{{margin:4px 0;font-size:15px}}
.article li::marker{{color:var(--accent-mid)}}
.article strong{{font-weight:700}}
.article em{{color:var(--text-2)}}
.article a{{color:var(--accent);text-decoration:underline;text-decoration-color:rgba(15,95,115,.24);text-underline-offset:3px}}
.article hr{{border:none;border-top:1px solid var(--border);margin:20px 0}}
.article :not(pre)>code{{padding:1px 5px;border:1px solid var(--border);border-radius:4px;background:#f3f4f6;color:#9f1239;font-family:var(--font-mono);font-size:12px}}
.code-block{{position:relative;margin:20px 0;border:1px solid var(--code-border);border-radius:var(--radius-lg);overflow:hidden;box-shadow:0 8px 24px rgba(2,6,23,.2)}}
.code-lang{{position:absolute;top:0;left:0;padding:4px 12px;border-bottom-right-radius:8px;background:#213041;color:#8cb6c1;font-family:var(--font-mono);font-size:10px;letter-spacing:.08em;text-transform:uppercase}}
.copy-btn{{position:absolute;top:8px;right:10px;display:flex;align-items:center;padding:5px 8px;border:1px solid #3b4a5e;border-radius:6px;background:#243244;color:#8ca6bf;cursor:pointer;transition:background .15s ease,color .15s ease}}
.copy-btn:hover{{background:#31445c;color:#e2ecf6}}
.copy-btn.copied{{color:#9fe5b8;border-color:#4f7d63}}
.code-block pre{{margin:0;padding:36px 20px 20px;background:var(--code-bg);overflow-x:auto}}
.code-block code{{background:none;border:none;padding:0;color:var(--code-text);font-family:var(--font-mono);font-size:13px;line-height:1.7;white-space:pre}}
.table-wrap{{margin:16px 0;overflow-x:auto;border:1px solid var(--border);border-radius:var(--radius-lg);box-shadow:0 4px 16px rgba(15,23,42,.05)}}
table{{width:100%;min-width:360px;border-collapse:collapse;font-size:14px}}
thead{{background:#f9fafb}}
th{{padding:9px 14px;border-bottom:1px solid var(--border);color:var(--text-2);font-size:11.5px;font-weight:700;letter-spacing:.04em;text-align:left;text-transform:uppercase;white-space:nowrap}}
td{{padding:8px 14px;border-bottom:1px solid var(--border-soft);vertical-align:top;line-height:1.6}}
tbody tr:last-child td{{border-bottom:none}}
tbody tr:nth-child(even) td{{background:#fbfcfd}}
tbody tr:hover td{{background:var(--accent-light)}}
.badge-ok,.badge-err,.badge-warn{{display:inline-flex;align-items:center;gap:4px;padding:2px 9px;border-radius:999px;border:1px solid;font-size:13px;font-weight:600}}
.badge-ok{{background:var(--green-bg);color:var(--green);border-color:#abefc6}}
.badge-err{{background:var(--red-bg);color:var(--red);border-color:#fecdca}}
.badge-warn{{background:var(--amber-bg);color:var(--amber);border-color:#fed7aa}}
.global-warn{{margin:16px 0;padding:14px 18px;border:1px solid #fecdca;border-radius:var(--radius-lg);background:#fef3f2;color:#b42318;font-size:14px;font-weight:700}}
.tree-note{{margin:3px 0 3px 8px;padding:3px 0 3px 16px;border-left:2px solid var(--border-soft);color:var(--text-2);font-family:var(--font-mono);font-size:12.5px}}
.meta{{display:flex;justify-content:space-between;gap:16px;align-items:center;margin-top:44px;padding-top:16px;border-top:1px solid var(--border-soft);color:var(--text-3);font-size:12px}}
.meta-source{{font-family:var(--font-mono);font-size:11.5px}}
@media print{{body{{background:white}}#progress,.toc{{display:none}}.layout{{display:block;padding:0}}.article{{padding:24px;border:none;box-shadow:none}}.copy-btn{{display:none}}}}
@media(max-width:900px){{.layout{{padding:24px 16px 64px}}.toc{{display:none}}.article{{padding:36px 28px}}}}
@media(max-width:480px){{.article{{padding:24px 18px}}.article h1{{font-size:24px}}}}
</style>
</head>
<body>
<div id="progress"></div>
<div class="layout">
  {toc}
  <article class="article">
    {body}
    <div class="meta">
      <span class="meta-source">{source_name}</span>
      <span>生成于 {generated_at}</span>
    </div>
  </article>
</div>
<script>
window.addEventListener("scroll", () => {{
  const el = document.documentElement;
  const total = el.scrollHeight - el.clientHeight;
  const pct = total > 0 ? (el.scrollTop / total) * 100 : 0;
  document.getElementById("progress").style.width = Math.min(pct, 100) + "%";
}});
(function () {{
  const headings = Array.from(document.querySelectorAll("article h1, article h2, article h3"));
  const links = Array.from(document.querySelectorAll(".toc a"));
  if (!links.length) return;
  const observer = new IntersectionObserver((entries) => {{
    entries.forEach((entry) => {{
      if (!entry.isIntersecting) return;
      links.forEach((link) => link.classList.remove("active"));
      const link = links.find((item) => item.getAttribute("href") === "#" + entry.target.id);
      if (link) link.classList.add("active");
    }});
  }}, {{ rootMargin: "-10% 0px -80% 0px" }});
  headings.forEach((heading) => observer.observe(heading));
}})();
(function () {{
  let index = 0;
  document.querySelectorAll("article h2").forEach((heading) => {{
    index += 1;
    heading.setAttribute("data-index", String(index).padStart(2, "0"));
  }});
}})();
function copyCode(button) {{
  const code = button.closest(".code-block").querySelector("code").innerText;
  navigator.clipboard.writeText(code).then(() => {{
    button.classList.add("copied");
    button.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"></polyline></svg>';
    setTimeout(() => {{
      button.classList.remove("copied");
      button.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>';
    }}, 2000);
  }});
}}
</script>
</body>
</html>
"""

CODE_COPY_ICON = """<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
    <rect x="9" y="9" width="13" height="13" rx="2"></rect>
    <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
  </svg>"""

EMOJI_RE = re.compile(r"[\U0001F300-\U0001FAFF]")
TAG_RE = re.compile(r"<[^>]+>")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
FENCE_RE = re.compile(r"^```([\w.+-]*)\s*$")
ORDERED_RE = re.compile(r"^\d+\.\s+")
UNORDERED_RE = re.compile(r"^[-*+]\s+")
TABLE_ALIGN_RE = re.compile(r"^\|?(?:\s*:?-{3,}:?\s*\|)+\s*:?-{3,}:?\s*\|?\s*$")


def fail(message: str) -> None:
    sys.stderr.write(f"md_to_html 失败: {message}\n")
    raise SystemExit(1)


def read_json_stdin() -> Dict[str, object]:
    raw = sys.stdin.read().strip()
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        fail(f"无法解析工具输入 JSON: {error}")
    return {}


def resolve_path(file_path: object, workspace: Path) -> Optional[Path]:
    if not isinstance(file_path, str) or not file_path.strip():
        return None
    path = Path(file_path).expanduser()
    if path.is_absolute():
        return path.resolve()
    return (workspace / path).resolve()


def resolve_output_path(output_arg: object, input_file: Path, workspace: Path) -> Path:
    output = resolve_path(output_arg, workspace)
    if output is not None:
        return output
    return input_file.with_suffix(".html")


def clean_inline_text(text: object) -> str:
    value = str(text or "")
    value = TAG_RE.sub("", value)
    value = value.replace("*", "").replace("_", "").replace("`", "")
    value = EMOJI_RE.sub("", value)
    return value.strip()


def slugify(text: str) -> str:
    cleaned = clean_inline_text(text)
    cleaned = re.sub(r"[^\w\s-]", "", cleaned, flags=re.UNICODE)
    cleaned = re.sub(r"[\s_]+", "-", cleaned.strip().lower())[:60]
    return cleaned or "section"


def detect_page_title(markdown: str, fallback_stem: str) -> str:
    heading_match = re.search(r"^#\s+(.+)$", markdown, re.MULTILINE)
    report_match = re.search(r"服务器[^\n]{0,30}报告", markdown)
    title = heading_match.group(1) if heading_match else (report_match.group(0) if report_match else fallback_stem)
    title = clean_inline_text(title)
    return title or fallback_stem


def escape_attr(value: object) -> str:
    return html.escape(str(value or ""), quote=True)


def is_plain_text_report(markdown: str) -> bool:
    return (
        len(re.findall(r"【[^】]+】", markdown)) > 3
        or "===HEAVY===" in markdown
        or bool(re.search(r"^\s+\S+\s{3,}\S+\s{3,}\S+", markdown, re.MULTILINE))
    )


def try_convert_table(lines: List[str], start_index: int) -> Optional[Tuple[str, int]]:
    if lines[start_index].strip() != "---":
        return None

    header_index = start_index + 1
    while header_index < len(lines) and not lines[header_index].strip():
        header_index += 1
    if header_index >= len(lines) or lines[header_index].strip() == "---":
        return None

    separator_index = header_index + 1
    while separator_index < len(lines) and lines[separator_index].strip() != "---":
        separator_index += 1
    if separator_index >= len(lines):
        return None

    def split_columns(line: str) -> List[str]:
        return [part.strip() for part in re.split(r"  +", line.strip()) if part.strip()]

    headers = split_columns(lines[header_index])
    if len(headers) < 2:
        return None

    data_lines: List[str] = []
    row_index = separator_index + 1
    while row_index < len(lines):
        current = lines[row_index].strip()
        if current in {"---", "===HEAVY==="}:
            break
        if current:
            data_lines.append(lines[row_index])
        row_index += 1

    markdown_rows = [f"| {' | '.join(headers)} |", f"|{'|'.join(' --- ' for _ in headers)}|"]
    for line in data_lines:
        columns = split_columns(line)
        while len(columns) < len(headers):
            columns.append("")
        markdown_rows.append(f"| {' | '.join(columns[: len(headers)])} |")

    next_index = row_index + 1 if row_index < len(lines) and lines[row_index].strip() == "---" else row_index
    return ("\n" + "\n".join(markdown_rows) + "\n", next_index)


def preprocess_plain_text(markdown: str) -> str:
    lines = markdown.splitlines()
    output: List[str] = []
    index = 0

    while index < len(lines):
        line = lines[index]
        stripped = line.strip()

        if stripped == "===HEAVY===":
            title_index = index + 1
            while title_index < len(lines) and not lines[title_index].strip():
                title_index += 1
            if title_index < len(lines) and lines[title_index].strip() != "===HEAVY===":
                title = lines[title_index].strip()
                tail_index = title_index + 1
                while tail_index < len(lines) and not lines[tail_index].strip():
                    tail_index += 1
                if tail_index < len(lines) and lines[tail_index].strip() == "===HEAVY===":
                    output.append(f"\n## {title}\n")
                    index = tail_index + 1
                    continue
            output.append("---")
            index += 1
            continue

        if stripped == "---":
            table_result = try_convert_table(lines, index)
            if table_result is not None:
                markdown_table, next_index = table_result
                output.append(markdown_table)
                index = next_index
                continue
            output.append("")
            index += 1
            continue

        block_match = re.match(r"^【([^】]+)】\s*(.*)$", stripped)
        if block_match:
            suffix = f" {block_match.group(2)}" if block_match.group(2) else ""
            output.append(f"\n### {block_match.group(1)}{suffix}\n")
            index += 1
            continue

        output.append(line)
        index += 1

    return "\n".join(output)


def parse_inline(text: str) -> str:
    placeholders: List[str] = []

    def stash(raw: str) -> str:
        placeholders.append(raw)
        return f"\x00{len(placeholders) - 1}\x00"

    escaped = html.escape(text, quote=False)
    escaped = re.sub(r"`([^`]+)`", lambda m: stash(f"<code>{html.escape(m.group(1))}</code>"), escaped)
    escaped = re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        lambda m: f'<a href="{escape_attr(m.group(2).strip())}">{m.group(1).strip()}</a>',
        escaped,
    )
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"__(.+?)__", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", r"<em>\1</em>", escaped)
    escaped = re.sub(r"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)", r"<em>\1</em>", escaped)

    for index, value in enumerate(placeholders):
        escaped = escaped.replace(f"\x00{index}\x00", value)
    return escaped


def render_code_block(code: str, lang: str) -> str:
    lang_label = f'<span class="code-lang">{escape_attr(lang)}</span>' if lang else ""
    return (
        f'<div class="code-block">{lang_label}\n'
        f'<button class="copy-btn" onclick="copyCode(this)" title="复制代码" aria-label="复制代码">\n'
        f"  {CODE_COPY_ICON}\n"
        f"</button>\n<pre><code>{html.escape(code)}</code></pre></div>"
    )


def split_table_row(line: str) -> List[str]:
    stripped = line.strip()
    if stripped.startswith("|"):
        stripped = stripped[1:]
    if stripped.endswith("|"):
        stripped = stripped[:-1]
    return [cell.strip() for cell in stripped.split("|")]


def render_table(lines: List[str]) -> str:
    headers = split_table_row(lines[0])
    rows = [split_table_row(line) for line in lines[2:]]
    thead = "<thead><tr>" + "".join(f"<th>{parse_inline(cell)}</th>" for cell in headers) + "</tr></thead>"
    body_rows = []
    for row in rows:
        while len(row) < len(headers):
            row.append("")
        body_rows.append("<tr>" + "".join(f"<td>{parse_inline(cell)}</td>" for cell in row[: len(headers)]) + "</tr>")
    tbody = f"<tbody>{''.join(body_rows)}</tbody>" if body_rows else ""
    return f'<div class="table-wrap"><table>{thead}{tbody}</table></div>'


def collect_paragraph(lines: List[str], start: int) -> Tuple[str, int]:
    parts: List[str] = []
    index = start
    while index < len(lines):
        stripped = lines[index].strip()
        if not stripped:
            break
        if (
            HEADING_RE.match(stripped)
            or FENCE_RE.match(stripped)
            or stripped == "```"
            or stripped in {"---", "***", "___"}
            or stripped.startswith(">")
            or UNORDERED_RE.match(stripped)
            or ORDERED_RE.match(stripped)
            or is_table_start(lines, index)
        ):
            break
        parts.append(stripped)
        index += 1
    return (" ".join(parts), index)


def is_table_start(lines: List[str], index: int) -> bool:
    if index + 1 >= len(lines):
        return False
    return "|" in lines[index] and bool(TABLE_ALIGN_RE.match(lines[index + 1].strip()))


def collect_list(lines: List[str], start: int, ordered: bool) -> Tuple[str, int]:
    regex = ORDERED_RE if ordered else UNORDERED_RE
    tag = "ol" if ordered else "ul"
    items: List[str] = []
    index = start
    while index < len(lines):
        stripped = lines[index].strip()
        if not stripped:
            if index + 1 < len(lines) and regex.match(lines[index + 1].strip()):
                index += 1
                continue
            break
        match = regex.match(stripped)
        if not match:
            break
        items.append(f"<li>{parse_inline(stripped[match.end():].strip())}</li>")
        index += 1
    return (f"<{tag}>{''.join(items)}</{tag}>", index)


def collect_blockquote(lines: List[str], start: int) -> Tuple[str, int]:
    parts: List[str] = []
    index = start
    while index < len(lines):
        stripped = lines[index].strip()
        if not stripped.startswith(">"):
            break
        parts.append(parse_inline(stripped[1:].lstrip()))
        index += 1
    return ("<blockquote><p>" + "<br>".join(parts) + "</p></blockquote>", index)


def render_markdown(markdown: str) -> Tuple[str, List[Dict[str, object]]]:
    lines = markdown.splitlines()
    output: List[str] = []
    toc_items: List[Dict[str, object]] = []
    slug_counts: Dict[str, int] = {}
    index = 0

    while index < len(lines):
        line = lines[index]
        stripped = line.strip()

        if not stripped:
            index += 1
            continue

        heading_match = HEADING_RE.match(stripped)
        if heading_match:
            level = len(heading_match.group(1))
            inner = heading_match.group(2).strip()
            plain = clean_inline_text(inner)
            slug = slugify(plain)
            count = slug_counts.get(slug, 0)
            slug_counts[slug] = count + 1
            anchor = f"h-{slug}" if count == 0 else f"h-{slug}-{count + 1}"
            toc_items.append({"level": level, "text": plain, "id": anchor})
            output.append(f'<h{level} id="{escape_attr(anchor)}">{parse_inline(inner)}</h{level}>')
            index += 1
            continue

        fence_match = FENCE_RE.match(stripped) or (re.match(r"^```$", stripped))
        if fence_match:
            lang = fence_match.group(1).strip() if hasattr(fence_match, "group") and fence_match.group(1) else ""
            index += 1
            code_lines: List[str] = []
            while index < len(lines) and lines[index].strip() != "```":
                code_lines.append(lines[index])
                index += 1
            if index < len(lines) and lines[index].strip() == "```":
                index += 1
            output.append(render_code_block("\n".join(code_lines), lang))
            continue

        if stripped in {"---", "***", "___"}:
            output.append("<hr>")
            index += 1
            continue

        if is_table_start(lines, index):
            table_lines = [lines[index], lines[index + 1]]
            index += 2
            while index < len(lines) and lines[index].strip() and "|" in lines[index]:
                table_lines.append(lines[index])
                index += 1
            output.append(render_table(table_lines))
            continue

        if stripped.startswith(">"):
            block_html, index = collect_blockquote(lines, index)
            output.append(block_html)
            continue

        if UNORDERED_RE.match(stripped):
            list_html, index = collect_list(lines, index, ordered=False)
            output.append(list_html)
            continue

        if ORDERED_RE.match(stripped):
            list_html, index = collect_list(lines, index, ordered=True)
            output.append(list_html)
            continue

        paragraph, index = collect_paragraph(lines, index)
        if paragraph:
            output.append(f"<p>{parse_inline(paragraph)}</p>")
            continue

        index += 1

    return ("\n".join(output), toc_items)


def build_toc(items: List[Dict[str, object]]) -> str:
    filtered = [item for item in items if int(item["level"]) <= 3]
    if sum(1 for item in filtered if int(item["level"]) <= 2) < 2:
        return ""
    links = "\n  ".join(
        f'<a href="#{escape_attr(item["id"])}" class="toc-l{int(item["level"])}">{escape_attr(item["text"])}</a>'
        for item in filtered
    )
    return f'<nav class="toc" id="toc">\n  <div class="toc-title">目录</div>\n  {links}\n</nav>'


def badge_status(text: str) -> str:
    value = text.strip()
    if "✅" in value:
        return f'<span class="badge-ok">{value}</span>'
    if "❌" in value:
        return f'<span class="badge-err">{value}</span>'
    if "⚠" in value:
        return f'<span class="badge-warn">{value}</span>'
    return value


def enrich_report_html(body_html: str) -> str:
    body_html = re.sub(
        r"<td>(([^<]*)(✅|❌|⚠️|⚠)[^<]*)</td>",
        lambda m: f"<td>{badge_status(m.group(1))}</td>",
        body_html,
    )
    body_html = re.sub(
        r"<p>([^<]*🔴[^<]*全局警告[^<]*)</p>",
        lambda m: f'<div class="global-warn">{m.group(1)}</div>',
        body_html,
    )
    body_html = re.sub(
        r"<p>([^<]*[└├][─][^<]*)</p>",
        lambda m: f'<p class="tree-note">{m.group(1)}</p>',
        body_html,
    )
    body_html = re.sub(r"</ul>\s*<ul>", "", body_html)
    return body_html


def build_html(title: str, toc_html: str, body_html: str, source_name: str, generated_at: str) -> str:
    return STYLE.format(
        title=escape_attr(title),
        toc=toc_html,
        body=body_html,
        source_name=escape_attr(source_name),
        generated_at=escape_attr(generated_at),
    )


def main() -> None:
    payload = read_json_stdin()
    args = payload.get("args", {}) if isinstance(payload, dict) else {}
    context = payload.get("context", {}) if isinstance(payload, dict) else {}

    workspace_root = (
        Path(str(context.get("worktree") or context.get("directory") or os.environ.get("XIAOO_WORKSPACE_ROOT") or os.getcwd()))
        .expanduser()
        .resolve()
    )

    input_path = resolve_path(args.get("input_path"), workspace_root) if isinstance(args, dict) else None
    if input_path is None:
        fail("缺少必填参数 input_path")

    output_path = resolve_output_path(args.get("output_path") if isinstance(args, dict) else None, input_path, workspace_root)
    custom_title = clean_inline_text(args.get("title")) if isinstance(args, dict) else ""
    force_report_mode = bool(args.get("force_report_mode")) if isinstance(args, dict) else False
    disable_toc = bool(args.get("disable_toc")) if isinstance(args, dict) else False

    try:
        md_content = input_path.read_text(encoding="utf-8")
    except OSError as error:
        fail(f"无法读取 Markdown 文件: {input_path}\n{error}")

    is_report = force_report_mode or is_plain_text_report(md_content)
    processed_markdown = preprocess_plain_text(md_content) if is_report else md_content
    body_html, toc_items = render_markdown(processed_markdown)
    if is_report:
        body_html = enrich_report_html(body_html)

    page_title = custom_title or detect_page_title(md_content, input_path.stem)
    toc_html = "" if disable_toc else build_toc(toc_items)
    has_toc = bool(toc_html)
    generated_at = dt.datetime.now().strftime("%Y/%m/%d %H:%M")
    full_html = build_html(page_title, toc_html, body_html, input_path.name, generated_at)

    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(full_html, encoding="utf-8")
    except OSError as error:
        fail(f"写出 HTML 文件失败: {output_path}\n{error}")

    sys.stdout.write(
        "\n".join(
            [
                "Markdown 已转换为 HTML",
                f"输入文件: {input_path}",
                f"输出文件: {output_path}",
                f"报告增强: {'已启用' if is_report else '未启用'}",
                f"目录生成: {'已启用' if has_toc else '未启用'}",
                f"页面标题: {page_title}",
            ]
        )
    )


if __name__ == "__main__":
    main()
