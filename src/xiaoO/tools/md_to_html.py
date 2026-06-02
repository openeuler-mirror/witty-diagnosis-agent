#!/usr/bin/env python3

import html
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Tuple


COPY_ICON = (
    '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">'
    '<rect x="9" y="9" width="13" height="13" rx="2"></rect>'
    '<path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>'
    "</svg>"
)


@dataclass
class Heading:
    level: int
    text: str
    anchor_id: str


def fail(message: str) -> None:
    sys.stderr.write(f"md_to_html 失败: {message}\n")
    raise SystemExit(1)


def read_json_stdin() -> dict:
    raw = sys.stdin.read().strip()
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"无法解析工具输入 JSON: {exc}")


def resolve_path(file_path: Optional[str], workspace: str) -> Optional[Path]:
    if not isinstance(file_path, str) or not file_path.strip():
        return None
    path = Path(file_path).expanduser()
    if path.is_absolute():
        return path.resolve()
    return (Path(workspace) / path).resolve()


def resolve_output_path(output_arg: Optional[str], input_file: Path, workspace: str) -> Path:
    resolved = resolve_path(output_arg, workspace)
    if resolved is not None:
        return resolved
    return input_file.with_suffix(".html")


def clean_inline_text(text: str) -> str:
    value = str(text or "")
    value = re.sub(r"<[^>]+>", "", value)
    value = re.sub(r"[*_`]", "", value)
    value = re.sub(r"[\U0001F300-\U0001FAFF]", "", value)
    return value.strip()


def slugify(text: str) -> str:
    cleaned = clean_inline_text(text)
    cleaned = re.sub(r"[^\w\s-]", "", cleaned, flags=re.UNICODE)
    cleaned = re.sub(r"\s+", "-", cleaned.strip()).lower()[:60]
    return cleaned or "section"


def detect_page_title(markdown: str, fallback_stem: str) -> str:
    heading_match = re.search(r"^#\s+(.+)$", markdown, flags=re.MULTILINE)
    report_match = re.search(r"服务器[^\n]{0,30}报告", markdown)
    title = None
    if heading_match:
        title = heading_match.group(1)
    elif report_match:
        title = report_match.group(0)
    else:
        title = fallback_stem
    cleaned = clean_inline_text(title)
    return cleaned or fallback_stem


def build_toc(items: List[Heading]) -> str:
    filtered = [item for item in items if item.level <= 3]
    if len([item for item in filtered if item.level <= 2]) < 2:
        return ""
    links = "\n  ".join(
        f'<a href="#{escape_html(item.anchor_id)}" class="toc-l{item.level}">{escape_html(item.text)}</a>'
        for item in filtered
    )
    return f'<nav class="toc" id="toc">\n  <div class="toc-title">目录</div>\n  {links}\n</nav>'


def badge_status(text: str) -> str:
    value = (text or "").strip()
    if "✅" in value:
        return f'<span class="badge-ok">{value}</span>'
    if "❌" in value:
        return f'<span class="badge-err">{value}</span>'
    if "⚠" in value:
        return f'<span class="badge-warn">{value}</span>'
    return value


def enrich_report_html(raw_html: str) -> str:
    value = re.sub(
        r"<td>(([^<]*)(✅|❌|⚠️|⚠)[^<]*)</td>",
        lambda match: f"<td>{badge_status(match.group(1))}</td>",
        raw_html,
    )
    value = re.sub(
        r"<p>([^<]*🔴[^<]*全局警告[^<]*)</p>",
        lambda match: f'<div class="global-warn">{match.group(1)}</div>',
        value,
    )
    value = re.sub(
        r"<p>([^<]*[└├][─][^<]*)</p>",
        lambda match: f'<p class="tree-note">{match.group(1)}</p>',
        value,
    )
    value = re.sub(r"</ul>\s*<ul>", "", value)
    return value


def is_plain_text_report(markdown: str) -> bool:
    return (
        len(re.findall(r"【[^】]+】", markdown)) > 3
        or "===HEAVY===" in markdown
        or bool(re.search(r"^\s+\S+\s{3,}\S+\s{3,}\S+", markdown, flags=re.MULTILINE))
    )


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
                    output.extend(["", f"## {title}", ""])
                    index = tail_index + 1
                    continue
            output.append("---")
            index += 1
            continue

        if stripped == "---":
            table_result = try_convert_table(lines, index)
            if table_result is not None:
                markdown_table, next_index = table_result
                output.extend(["", markdown_table, ""])
                index = next_index
                continue
            output.append("")
            index += 1
            continue

        block_match = re.match(r"^【([^】]+)】\s*(.*)$", stripped)
        if block_match:
            heading = block_match.group(1)
            extra = block_match.group(2)
            output.extend(["", f"### {heading}{(' ' + extra) if extra else ''}", ""])
            index += 1
            continue

        output.append(line)
        index += 1

    return "\n".join(output)


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

    rows: List[str] = []
    row_index = separator_index + 1
    while row_index < len(lines):
        current = lines[row_index].strip()
        if current in {"---", "===HEAVY==="}:
            break
        if current:
            cols = split_columns(lines[row_index])
            while len(cols) < len(headers):
                cols.append("")
            rows.append(f"| {' | '.join(cols[:len(headers)])} |")
        row_index += 1

    next_index = row_index + 1 if row_index < len(lines) and lines[row_index].strip() == "---" else row_index
    table_lines = [
        f"| {' | '.join(headers)} |",
        "|" + "|".join(" --- " for _ in headers) + "|",
        *rows,
    ]
    return "\n".join(table_lines), next_index


def escape_html(value: str) -> str:
    return html.escape(str(value or ""), quote=True)


def render_inline(text: str) -> str:
    placeholders: List[str] = []

    def stash(value: str) -> str:
        placeholders.append(value)
        return f"\x00{len(placeholders) - 1}\x00"

    escaped = escape_html(text)
    escaped = re.sub(
        r"`([^`\n]+)`",
        lambda m: stash(f"<code>{m.group(1)}</code>"),
        escaped,
    )
    escaped = re.sub(
        r"\[([^\]]+)\]\(([^)]+)\)",
        lambda m: stash(
            f'<a href="{escape_html(html.unescape(m.group(2)).strip())}">{m.group(1)}</a>'
        ),
        escaped,
    )
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"__([^_]+)__", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", escaped)
    escaped = re.sub(r"(?<!_)_([^_\n]+)_(?!_)", r"<em>\1</em>", escaped)
    escaped = escaped.replace("  \n", "<br>\n")
    for index, value in enumerate(placeholders):
        escaped = escaped.replace(f"\x00{index}\x00", value)
    return escaped


def strip_inline_markup(text: str) -> str:
    value = re.sub(r"`([^`]+)`", r"\1", text)
    value = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1", value)
    value = re.sub(r"[*_]+", "", value)
    return clean_inline_text(value)


def is_table_divider(line: str) -> bool:
    stripped = line.strip()
    return bool(re.fullmatch(r"\|?[\s:-]+\|[\s|:-]*", stripped)) and "-" in stripped


def split_table_row(line: str) -> List[str]:
    stripped = line.strip()
    if stripped.startswith("|"):
        stripped = stripped[1:]
    if stripped.endswith("|"):
        stripped = stripped[:-1]
    return [cell.strip() for cell in stripped.split("|")]


def render_code_block(code: str, language: str) -> str:
    lang_label = f'<span class="code-lang">{escape_html(language)}</span>' if language else ""
    return (
        '<div class="code-block">'
        f"{lang_label}"
        f'<button class="copy-btn" onclick="copyCode(this)" title="复制代码" aria-label="复制代码">{COPY_ICON}</button>'
        f"<pre><code>{escape_html(code)}</code></pre></div>"
    )


def render_table(headers: List[str], rows: List[List[str]]) -> str:
    thead = "".join(f"<th>{render_inline(cell)}</th>" for cell in headers)
    body_rows = []
    for row in rows:
        padded = row + [""] * (len(headers) - len(row))
        cells = "".join(f"<td>{render_inline(cell)}</td>" for cell in padded[: len(headers)])
        body_rows.append(f"<tr>{cells}</tr>")
    tbody = "".join(body_rows)
    return f'<div class="table-wrap"><table><thead><tr>{thead}</tr></thead><tbody>{tbody}</tbody></table></div>'


def render_list(lines: List[str], ordered: bool) -> str:
    tag = "ol" if ordered else "ul"
    items = []
    pattern = r"^\s*\d+[.)]\s+" if ordered else r"^\s*[-*+]\s+"
    for line in lines:
        content = re.sub(pattern, "", line, count=1)
        items.append(f"<li>{render_inline(content.strip())}</li>")
    return f"<{tag}>{''.join(items)}</{tag}>"


def render_markdown(markdown: str) -> Tuple[str, List[Heading]]:
    lines = markdown.splitlines()
    blocks: List[str] = []
    headings: List[Heading] = []
    index = 0

    while index < len(lines):
        line = lines[index]
        stripped = line.strip()

        if not stripped:
            index += 1
            continue

        fence_match = re.match(r"^```([^\s`]*)\s*$", stripped)
        if fence_match:
            language = fence_match.group(1).strip()
            code_lines = []
            index += 1
            while index < len(lines) and not re.match(r"^```", lines[index].strip()):
                code_lines.append(lines[index])
                index += 1
            if index < len(lines):
                index += 1
            blocks.append(render_code_block("\n".join(code_lines), language))
            continue

        heading_match = re.match(r"^(#{1,6})\s+(.+)$", stripped)
        if heading_match:
            level = len(heading_match.group(1))
            title_md = heading_match.group(2).strip()
            plain_text = strip_inline_markup(title_md)
            anchor_id = f"h-{slugify(plain_text)}"
            headings.append(Heading(level=level, text=plain_text, anchor_id=anchor_id))
            blocks.append(f'<h{level} id="{escape_html(anchor_id)}">{render_inline(title_md)}</h{level}>')
            index += 1
            continue

        if re.fullmatch(r"[-*_]{3,}", stripped):
            blocks.append("<hr>")
            index += 1
            continue

        if "|" in stripped and index + 1 < len(lines) and is_table_divider(lines[index + 1]):
            headers = split_table_row(line)
            row_index = index + 2
            rows: List[List[str]] = []
            while row_index < len(lines) and lines[row_index].strip() and "|" in lines[row_index]:
                rows.append(split_table_row(lines[row_index]))
                row_index += 1
            blocks.append(render_table(headers, rows))
            index = row_index
            continue

        if re.match(r"^\s*[-*+]\s+", line):
            list_lines = []
            while index < len(lines) and re.match(r"^\s*[-*+]\s+", lines[index]):
                list_lines.append(lines[index])
                index += 1
            blocks.append(render_list(list_lines, ordered=False))
            continue

        if re.match(r"^\s*\d+[.)]\s+", line):
            list_lines = []
            while index < len(lines) and re.match(r"^\s*\d+[.)]\s+", lines[index]):
                list_lines.append(lines[index])
                index += 1
            blocks.append(render_list(list_lines, ordered=True))
            continue

        paragraph_lines = [line]
        index += 1
        while index < len(lines):
            peek = lines[index]
            if not peek.strip():
                index += 1
                break
            if re.match(r"^```", peek.strip()) or re.match(r"^(#{1,6})\s+", peek.strip()):
                break
            if re.fullmatch(r"[-*_]{3,}", peek.strip()):
                break
            if "|" in peek and index + 1 < len(lines) and is_table_divider(lines[index + 1]):
                break
            if re.match(r"^\s*[-*+]\s+", peek) or re.match(r"^\s*\d+[.)]\s+", peek):
                break
            paragraph_lines.append(peek)
            index += 1
        paragraph = "\n".join(paragraph_lines)
        blocks.append(f"<p>{render_inline(paragraph)}</p>")

    return "\n".join(blocks), headings


def load_asset(name: str) -> str:
    asset_path = Path(__file__).with_name(name)
    try:
        return asset_path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"无法读取资源文件 {asset_path}: {exc}")


def main() -> None:
    payload = read_json_stdin()
    args = payload.get("args") or {}
    context = payload.get("context") or {}
    workspace_root = (
        context.get("worktree")
        or context.get("directory")
        or os.environ.get("XIAOO_WORKSPACE_ROOT")
        or os.getcwd()
    )

    input_path = resolve_path(args.get("input_path"), workspace_root)
    if not args.get("input_path") or input_path is None:
        fail("缺少必填参数 input_path")

    output_path = resolve_output_path(args.get("output_path"), input_path, workspace_root)
    custom_title = clean_inline_text(args.get("title", ""))
    force_report_mode = bool(args.get("force_report_mode"))
    disable_toc = bool(args.get("disable_toc"))

    try:
        md_content = input_path.read_text(encoding="utf-8")
    except OSError as exc:
        fail(f"无法读取 Markdown 文件: {input_path}\n{exc}")

    is_report = force_report_mode or is_plain_text_report(md_content)
    processed_markdown = preprocess_plain_text(md_content) if is_report else md_content
    body_html, toc_items = render_markdown(processed_markdown)
    if is_report:
        body_html = enrich_report_html(body_html)

    page_title = custom_title or detect_page_title(md_content, input_path.stem)
    toc_html = "" if disable_toc else build_toc(toc_items)
    has_toc = bool(toc_html)
    generated_at = datetime.now().strftime("%Y/%m/%d %H:%M")
    style_css = load_asset("md_to_html_style.css")
    script_js = load_asset("md_to_html_script.js")

    full_html = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{escape_html(page_title)}</title>
<style>
{style_css}
</style>
</head>
<body>
<div id="progress"></div>
<div class="layout">
  {toc_html if has_toc else ""}
  <article class="article">
    {body_html}
    <div class="meta">
      <span class="meta-source">{escape_html(input_path.name)}</span>
      <span>生成于 {escape_html(generated_at)}</span>
    </div>
  </article>
</div>
<script>
{script_js}
</script>
</body>
</html>"""

    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(full_html, encoding="utf-8")
    except OSError as exc:
        fail(f"写出 HTML 文件失败: {output_path}\n{exc}")

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
