import { readFileSync, writeFileSync } from "node:fs"
import { resolve, dirname, basename, extname, join } from "node:path"
import { marked } from "marked"
import type { PluginInput } from "@opencode-ai/plugin"
import { tool, type ToolDefinition } from "@opencode-ai/plugin/tool"

export function createReportVisualizationTool(ctx: PluginInput): Record<string, ToolDefinition> {
  const report_visualization: ToolDefinition = tool({
    description: "Converts a Markdown file into an HTML file for visualization. The output HTML file path will be returned.",
    args: {
      markdown_path: tool.schema.string().describe("The absolute path to the input Markdown file"),
    },
    execute: async (args, context) => {
      try {
        const inputPath = resolve(args.markdown_path)
        const outputDir = dirname(inputPath)
        const outputName = basename(inputPath, extname(inputPath)) + ".html"
        const outputPath = join(outputDir, outputName)

        let mdContent: string
        try {
          mdContent = readFileSync(inputPath, "utf-8")
        } catch (err: any) {
          return `Error reading file: ${inputPath}\n${err.message}`
        }

        // 预处理：修复 ASCII 报表在 Markdown 解析时的格式崩坏问题
        // 1. 将长串的 = 替换为粗分割线
        mdContent = mdContent.replace(/^={10,}\s*$/gm, '<hr class="heavy">')
        // 2. 将长串的 - 替换为细分割线
        mdContent = mdContent.replace(/^-{10,}\s*$/gm, '<hr>')

        // ── 自定义 Renderer：给标题注入 id，代码块注入 data-lang ──────────────────
        const renderer = new marked.Renderer()
        const tocItems: { level: number; text: string; id: string }[] = []

        renderer.heading = function (text, level) {
          const id = "h-" + text
            .replace(/<[^>]+>/g, "")
            .replace(/[^\p{L}\p{N}\s-]/gu, "")
            .trim()
            .replace(/\s+/g, "-")
            .toLowerCase()
            .slice(0, 60)
          tocItems.push({ level, text: text.replace(/<[^>]+>/g, ""), id })
          return `<h${level} id="${id}">${text}</h${level}>\n`
        }

        renderer.code = function (code, lang) {
          const safeLang = lang ? lang.trim() : ""
          const langLabel = safeLang ? `<span class="code-lang">${safeLang}</span>` : ""
          const escaped = code
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
          return `<div class="code-block">
  ${langLabel}
  <button class="copy-btn" onclick="copyCode(this)" title="复制">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>
  </button>
  <pre><code>${escaped}</code></pre>
</div>\n`
        }

        renderer.table = function (header, body) {
          return `<div class="table-wrap"><table><thead>${header}</thead><tbody>${body}</tbody></table></div>\n`
        }

        marked.setOptions({ renderer, gfm: true, breaks: false })
        const bodyHTML = await marked.parse(mdContent)

        // ── 生成目录 HTML ──────────────────────────────────────────────────────────
        function buildToc(items: { level: number; text: string; id: string }[]) {
          const filtered = items.filter(i => i.level <= 3)
          if (filtered.filter(i => i.level <= 2).length < 2) return ""
          
          let html = `<nav class="toc" id="toc">\n  <div class="toc-title">目录</div>\n  <div class="toc-content">\n`
          let currentLevel = 0
          
          filtered.forEach((item, index) => {
            const nextItem = filtered[index + 1]
            const hasChildren = nextItem && nextItem.level > item.level
            const cls = `toc-l${item.level}`
            
            if (item.level > currentLevel) {
              if (currentLevel !== 0) html += `<div class="toc-group" id="group-${item.id}">\n`
            } else if (item.level < currentLevel) {
              for (let i = 0; i < currentLevel - item.level; i++) {
                html += `</div>\n`
              }
            }
            
            html += `<div class="toc-item ${hasChildren ? 'has-children' : ''}">`
            if (hasChildren) {
              html += `<button class="toc-toggle" onclick="toggleToc(this)" aria-expanded="true">
                <svg viewBox="0 0 24 24" width="12" height="12" stroke="currentColor" stroke-width="2" fill="none"><polyline points="6 9 12 15 18 9"></polyline></svg>
              </button>`
            } else {
              html += `<span class="toc-spacer"></span>`
            }
            html += `<a href="#${item.id}" class="${cls}">${item.text}</a></div>\n`
            
            currentLevel = item.level
          })
          
          for (let i = 0; i < currentLevel - 1; i++) {
            html += `</div>\n`
          }
          
          html += `  </div>\n</nav>`
          return html
        }

        const tocHTML = buildToc(tocItems)
        const hasToc = tocHTML.length > 0
        const genTime = new Date().toLocaleString("zh-CN", {
          year: "numeric", month: "2-digit", day: "2-digit",
          hour: "2-digit", minute: "2-digit",
        })

        const titleMatch = mdContent.match(/^#\s+(.+)/m)
        const pageTitle = titleMatch ? titleMatch[1].replace(/[*_\`]/g, "") : outputName

        const fullHTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${pageTitle}</title>
<style>
  /* ── Design tokens ─────────────────────────────────────────────────────── */
  :root {
    --bg:          #f8f7f4;
    --surface:     #ffffff;
    --border:      #e8e5df;
    --border-soft: #f0ede8;

    --text:        #1c1917;
    --text-2:      #57534e;
    --text-3:      #a8a29e;

    --accent:      #1d4e6e;
    --accent-light:#e8f1f7;
    --accent-mid:  #3b82a0;

    --red:         #c0392b;

    --code-bg:     #1a1d27;
    --code-text:   #cdd6f4;
    --code-border: #2d3148;

    --font-body: -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Segoe UI", sans-serif;
    --font-head: -apple-system, BlinkMacSystemFont, "PingFang SC", Georgia, serif;
    --font-mono: "SF Mono", "Fira Code", "JetBrains Mono", Consolas, monospace;

    --radius:    8px;
    --radius-lg: 12px;
    --shadow:    0 1px 3px rgba(0,0,0,.06), 0 4px 16px rgba(0,0,0,.05);
    --shadow-lg: 0 2px 8px rgba(0,0,0,.07), 0 8px 32px rgba(0,0,0,.06);

    --toc-width:   240px;
    --gap:         32px;
  }

  /* ── Progress bar ──────────────────────────────────────────────────────── */
  #progress {
    position: fixed; top: 0; left: 0; height: 3px; width: 0%;
    background: linear-gradient(90deg, var(--accent-mid), var(--accent));
    z-index: 999; transition: width .1s linear;
    border-radius: 0 2px 2px 0;
  }

  /* ── Base ──────────────────────────────────────────────────────────────── */
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  html { font-size: 16px; scroll-behavior: smooth; }
  body {
    font-family: var(--font-body);
    background: var(--bg);
    color: var(--text);
    line-height: 1.8;
    -webkit-font-smoothing: antialiased;
  }

  /* ── Layout ────────────────────────────────────────────────────────────── */
  .layout {
    display: flex;
    align-items: flex-start;
    max-width: calc(var(--toc-width) + 900px + var(--gap) * 3);
    margin: 0 auto;
    padding: 48px var(--gap) 96px;
    gap: var(--gap);
  }

  /* ── TOC ───────────────────────────────────────────────────────────────── */
  .toc {
    width: var(--toc-width);
    flex-shrink: 0;
    position: sticky;
    top: 32px;
    max-height: calc(100vh - 64px);
    overflow-y: auto;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    padding: 20px;
    box-shadow: var(--shadow);
    scrollbar-width: thin;
    scrollbar-color: var(--border) transparent;
  }
  .toc-title {
    font-size: 10.5px;
    font-weight: 600;
    letter-spacing: .1em;
    text-transform: uppercase;
    color: var(--text-3);
    margin-bottom: 12px;
    padding-bottom: 10px;
    border-bottom: 1px solid var(--border-soft);
  }
  .toc-item {
    display: flex;
    align-items: flex-start;
    margin: 2px 0;
  }
  .toc-toggle {
    background: none;
    border: none;
    cursor: pointer;
    color: var(--text-3);
    padding: 4px;
    margin-right: 4px;
    margin-top: 2px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 4px;
    transition: background 0.2s, transform 0.2s;
  }
  .toc-toggle:hover { background: var(--border-soft); color: var(--text); }
  .toc-toggle[aria-expanded="false"] svg { transform: rotate(-90deg); }
  .toc-spacer { width: 20px; flex-shrink: 0; }
  .toc-group { overflow: hidden; transition: max-height 0.3s ease-in-out; }
  .toc-group.collapsed { max-height: 0 !important; }
  
  .toc a {
    display: block;
    font-size: 13px;
    color: var(--text-2);
    text-decoration: none;
    padding: 4px 8px;
    border-radius: 5px;
    line-height: 1.45;
    transition: background .15s, color .15s;
    word-break: break-all;
    flex-grow: 1;
  }
  .toc a:hover  { background: var(--accent-light); color: var(--accent); }
  .toc a.active { background: var(--accent-light); color: var(--accent); font-weight: 500; }
  .toc-l1 { font-weight: 600; color: var(--text); }
  .toc-l2 { font-size: 12.5px !important; }
  .toc-l3 { font-size: 12px !important; }

  /* ── Article card ──────────────────────────────────────────────────────── */
  .article {
    flex: 1; min-width: 0;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    padding: 56px 60px;
    box-shadow: var(--shadow-lg);
  }

  /* ── Headings ──────────────────────────────────────────────────────────── */
  .article h1 {
    font-family: var(--font-head);
    font-size: 28px; font-weight: 600; line-height: 1.3;
    color: var(--text); margin: 0 0 32px;
    padding-bottom: 20px;
    border-bottom: 2px solid var(--text);
    letter-spacing: -.3px;
  }
  .article h2 {
    font-family: var(--font-head);
    font-size: 19px; font-weight: 600;
    color: var(--text); margin: 52px 0 14px;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--border);
    letter-spacing: -.2px;
  }
  .article h2::before {
    content: attr(data-index);
    display: inline-block;
    font-family: var(--font-mono);
    font-size: 10.5px; font-weight: 500;
    color: var(--accent-mid);
    background: var(--accent-light);
    padding: 1px 7px; border-radius: 4px;
    margin-right: 10px; vertical-align: middle;
    letter-spacing: .05em;
  }
  .article h3 {
    font-family: var(--font-head);
    font-size: 15.5px; font-weight: 600;
    color: var(--text); margin: 32px 0 10px;
  }
  .article h3::before {
    content: "§ ";
    color: var(--text-3);
    font-family: var(--font-mono); font-size: 13px;
  }
  .article h4 {
    font-size: 13.5px; font-weight: 600;
    color: var(--text-2); margin: 22px 0 8px;
    text-transform: uppercase; letter-spacing: .05em;
  }

  /* ── Body text ─────────────────────────────────────────────────────────── */
  .article p { 
    font-size: 14.5px; 
    line-height: 1.85; 
    color: var(--text); 
    margin: 0 0 16px; 
    white-space: pre-wrap; 
    word-wrap: break-word;
    font-family: var(--font-mono);
  }
  .article strong { font-weight: 600; }
  .article em     { font-style: italic; color: var(--text-2); }
  .article a {
    color: var(--accent); text-decoration: underline;
    text-decoration-color: var(--accent-light);
    text-underline-offset: 3px;
    transition: text-decoration-color .2s;
  }
  .article a:hover { text-decoration-color: var(--accent); }
  .article hr { border: none; border-top: 1px solid var(--border); margin: 24px 0; }
  .article hr.heavy { border-top: 3px solid var(--text); margin: 32px 0; }

  /* ── Blockquote ────────────────────────────────────────────────────────── */
  .article blockquote {
    border-left: 3px solid var(--accent-mid);
    background: var(--accent-light);
    margin: 20px 0; padding: 13px 20px 13px 20px;
    border-radius: 0 var(--radius) var(--radius) 0;
  }
  .article blockquote p { font-size: 14.5px; color: var(--accent); margin: 0; line-height: 1.7; }
  .article blockquote strong { color: var(--accent); }

  /* ── Lists ─────────────────────────────────────────────────────────────── */
  .article ul, .article ol { padding-left: 22px; margin: 6px 0 16px; }
  .article li { font-size: 15px; line-height: 1.8; margin: 4px 0; }
  .article li::marker { color: var(--accent-mid); }
  .article li > ul, .article li > ol { margin: 3px 0; }

  /* ── Inline code ───────────────────────────────────────────────────────── */
  .article :not(pre) > code {
    font-family: var(--font-mono);
    font-size: 13px; font-weight: 500;
    background: #f3f0eb; color: var(--red);
    padding: 2px 6px; border-radius: 4px;
    border: 1px solid var(--border);
  }

  /* ── Code blocks ───────────────────────────────────────────────────────── */
  .code-block {
    position: relative; margin: 20px 0;
    border-radius: var(--radius-lg); overflow: hidden;
    border: 1px solid var(--code-border);
    box-shadow: 0 4px 20px rgba(0,0,0,.16);
  }
  .code-lang {
    position: absolute; top: 0; left: 0;
    font-family: var(--font-mono); font-size: 10px; font-weight: 500;
    color: #7c8db5; background: #222538;
    padding: 4px 12px; border-bottom-right-radius: 6px;
    text-transform: uppercase; letter-spacing: .08em;
    user-select: none;
  }
  .copy-btn {
    position: absolute; top: 8px; right: 10px;
    background: #2d3148; border: 1px solid #3d4260;
    border-radius: 5px; color: #7c8db5; cursor: pointer;
    padding: 5px 8px; display: flex; align-items: center;
    transition: background .15s, color .15s; z-index: 1;
  }
  .copy-btn:hover  { background: #3a3f60; color: #cdd6f4; }
  .copy-btn.copied { color: #a6e3a1; border-color: #4a6a4a; }
  .code-block pre {
    margin: 0; padding: 36px 20px 20px;
    background: var(--code-bg); overflow-x: auto;
    scrollbar-width: thin; scrollbar-color: #3d4260 transparent;
  }
  .code-block pre::-webkit-scrollbar { height: 5px; }
  .code-block pre::-webkit-scrollbar-thumb { background: #3d4260; border-radius: 3px; }
  .code-block code {
    font-family: var(--font-mono); font-size: 13px; line-height: 1.7;
    color: var(--code-text); background: none; border: none; padding: 0;
    white-space: pre; word-break: normal;
  }

  /* ── Tables ────────────────────────────────────────────────────────────── */
  .table-wrap {
    overflow-x: auto; margin: 20px 0;
    border-radius: var(--radius-lg);
    border: 1px solid var(--border);
    box-shadow: var(--shadow);
  }
  table { width: 100%; border-collapse: collapse; font-size: 14px; min-width: 360px; }
  thead { background: #f4f2ee; }
  th {
    padding: 10px 16px; text-align: left;
    font-size: 11.5px; font-weight: 600;
    letter-spacing: .04em; text-transform: uppercase;
    color: var(--text-2); border-bottom: 1px solid var(--border);
    white-space: nowrap;
  }
  td {
    padding: 9px 16px; border-bottom: 1px solid var(--border-soft);
    color: var(--text); vertical-align: top; line-height: 1.6;
  }
  tbody tr:last-child td { border-bottom: none; }
  tbody tr:nth-child(even) td { background: #faf9f7; }
  tbody tr:hover td { background: var(--accent-light); transition: background .1s; }

  /* ── Meta footer ───────────────────────────────────────────────────────── */
  .meta {
    margin-top: 56px; padding-top: 18px;
    border-top: 1px solid var(--border-soft);
    display: flex; justify-content: space-between; align-items: center;
    font-size: 12px; color: var(--text-3);
  }
  .meta-source { font-family: var(--font-mono); font-size: 11.5px; }

  /* ── Print ─────────────────────────────────────────────────────────────── */
  @media print {
    body { background: white; }
    #progress, .toc { display: none; }
    .layout { display: block; padding: 0; }
    .article { border: none; box-shadow: none; padding: 24px; }
    .copy-btn { display: none; }
  }

  /* ── Responsive ────────────────────────────────────────────────────────── */
  @media (max-width: 900px) {
    .toc { display: none; }
    .article { padding: 36px 28px; }
    .layout { padding: 24px 16px 64px; }
  }
  @media (max-width: 480px) {
    .article { padding: 24px 18px; }
    .article h1 { font-size: 22px; }
  }
</style>
</head>
<body>

<div id="progress"></div>

<div class="layout">
  ${hasToc ? tocHTML : ""}
  <article class="article" id="article">
    ${bodyHTML}
    <div class="meta">
      <span class="meta-source">${outputName.replace(".html", ".md")}</span>
      <span>生成于 ${genTime}</span>
    </div>
  </article>
</div>

<script>
  /* ── 滚动进度条 ── */
  window.addEventListener("scroll", () => {
    const el  = document.documentElement;
    const pct = el.scrollTop / (el.scrollHeight - el.clientHeight) * 100;
    document.getElementById("progress").style.width = Math.min(pct, 100) + "%";
  });

  /* ── TOC 高亮当前章节 ── */
  (function () {
    const headings = Array.from(document.querySelectorAll("article h1,article h2,article h3"));
    const links    = Array.from(document.querySelectorAll(".toc a"));
    if (!links.length) return;
    const obs = new IntersectionObserver(entries => {
      entries.forEach(e => {
        if (!e.isIntersecting) return;
        links.forEach(l => l.classList.remove("active"));
        const a = links.find(l => l.getAttribute("href") === "#" + e.target.id);
        if (a) a.classList.add("active");
      });
    }, { rootMargin: "-10% 0px -80% 0px" });
    headings.forEach(h => obs.observe(h));
  })();

  /* ── h2 章节序号自动计数 ── */
  (function () {
    let idx = 0;
    document.querySelectorAll("article h2").forEach(el => {
      idx++;
      el.setAttribute("data-index", String(idx).padStart(2, "0"));
    });
  })();

  /* ── 代码块一键复制 ── */
  function copyCode(btn) {
    const code = btn.closest(".code-block").querySelector("code").innerText;
    navigator.clipboard.writeText(code).then(() => {
      btn.classList.add("copied");
      btn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>';
      setTimeout(() => {
        btn.classList.remove("copied");
        btn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>';
      }, 2000);
    });
  }

  /* ── 目录树收缩/展开 ── */
  function toggleToc(btn) {
    const expanded = btn.getAttribute("aria-expanded") === "true";
    btn.setAttribute("aria-expanded", String(!expanded));
    const parentItem = btn.closest(".toc-item");
    let nextEl = parentItem.nextElementSibling;
    if (nextEl && nextEl.classList.contains("toc-group")) {
      if (expanded) {
        nextEl.style.maxHeight = nextEl.scrollHeight + "px";
        void nextEl.offsetHeight;
        nextEl.classList.add("collapsed");
      } else {
        nextEl.classList.remove("collapsed");
        nextEl.style.maxHeight = nextEl.scrollHeight + "px";
        setTimeout(() => {
          if (!nextEl.classList.contains("collapsed")) {
            nextEl.style.maxHeight = "none";
          }
        }, 300);
      }
    }
  }
</script>
</body>
</html>`

        try {
          writeFileSync(outputPath, fullHTML, "utf-8")
          return `Successfully converted to HTML: ${outputPath}`
        } catch (err: any) {
          return `Error writing HTML file: ${outputPath}\n${err.message}`
        }
      } catch (e: any) {
        return `Error: ${e.message}`
      }
    },
  })

  return { report_visualization }
}
