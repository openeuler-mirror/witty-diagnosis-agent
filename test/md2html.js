#!/usr/bin/env node
/**
 * md2html.js — Markdown → 精排 HTML 独立页面
 *
 * 用法:  node md2html.js <markdown文件路径>
 * 输出:  同目录下同名 .html 文件
 * 依赖:  npm install marked
 *
 * 亮点：内置「纯文本报告后处理器」
 *   针对用空格对齐的纯文本表格、【】标题、时间线、故障分级等
 *   结构识别并渲染为美观 UI 组件，无需修改源 Markdown。
 */

import { readFileSync, writeFileSync } from "fs";
import { resolve, dirname, basename, extname, join } from "path";
import { marked } from "marked";

// ── 参数 ───────────────────────────────────────────────────────────────────
const inputArg = process.argv[2];
if (!inputArg) {
  console.error("用法: node md2html.js <markdown文件路径>");
  process.exit(1);
}
const inputPath  = resolve(inputArg);
const outputDir  = dirname(inputPath);
const stem       = basename(inputPath, extname(inputPath));
const outputPath = join(outputDir, stem + ".html");

let mdContent;
try {
  mdContent = readFileSync(inputPath, "utf-8");
} catch (e) {
  console.error(`❌ 无法读取: ${inputPath}\n${e.message}`);
  process.exit(1);
}

// ══════════════════════════════════════════════════════════════════
// 1. marked 渲染（标准 GFM）
// ══════════════════════════════════════════════════════════════════
const renderer = new marked.Renderer();
const tocItems  = [];

renderer.heading = (text, level) => {
  const id = "h-" + text.replace(/<[^>]+>/g,"")
    .replace(/[^\p{L}\p{N}\s-]/gu,"").trim()
    .replace(/\s+/g,"-").toLowerCase().slice(0,60);
  tocItems.push({ level, text: text.replace(/<[^>]+>/g,""), id });
  return `<h${level} id="${id}">${text}</h${level}>\n`;
};

renderer.code = (code, lang) => {
  const safeLang  = lang ? lang.trim() : "";
  const langLabel = safeLang ? `<span class="code-lang">${safeLang}</span>` : "";
  const escaped   = code.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
  return `<div class="code-block">${langLabel}
<button class="copy-btn" onclick="copyCode(this)" title="复制">
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
    <rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/>
  </svg></button>
<pre><code>${escaped}</code></pre></div>\n`;
};

renderer.table = (header, body) =>
  `<div class="table-wrap"><table><thead>${header}</thead><tbody>${body}</tbody></table></div>\n`;

marked.setOptions({ renderer, gfm: true, breaks: false });

// ══════════════════════════════════════════════════════════════════
// 2. 后处理器：把裸 HTML 里的纯文本结构识别成 UI 组件
// ══════════════════════════════════════════════════════════════════
function postProcess(html) {
  // 把 HTML 转成行数组（保留已有 HTML 标签，仅对裸文本行操作）
  const lines = htmlToTextLines(html);
  const out   = [];
  let i = 0;

  while (i < lines.length) {
    const raw      = lines[i];
    const stripped = raw.replace(/<[^>]+>/g,"").trim();

    // ── 已有的 HTML 标签行（直接透传） ──────────────────────────
    if (/^<[^p]/.test(raw.trimStart()) || /^<p\s/.test(raw.trimStart())) {
      // <p> 内部可能有裸文本报告内容，继续处理
      if (/^<p[\s>]/.test(raw.trimStart())) {
        const inner = raw.replace(/^<p[^>]*>/,"").replace(/<\/p>$/,"");
        out.push(processInlineParagraph(inner, i, lines, out));
      } else {
        out.push(raw);
      }
      i++; continue;
    }

    // ── 纯文本段落（marked 生成的） ─────────────────────────────
    // 这是核心：对 <p> 里的裸文本做二次解析
    out.push(processInlineParagraph(stripped, i, lines, out));
    i++;
  }

  return out.join("\n");
}

/** 对单行裸文本识别结构 */
function processInlineParagraph(text, _i, _lines, _out) {
  if (!text.trim()) return "";

  const t = text.trim();

  // 🔴 全局警告行
  if (t.startsWith("🔴") && t.includes("全局警告"))
    return `<div class="global-warn">${esc(t)}</div>`;

  // 【PX ...】 故障优先级标题
  const pm = t.match(/^【(P[0-3][^】]*)】(.*)/);
  if (pm) {
    const level = pm[1]; const rest = pm[2].trim();
    const p = level.slice(0,2);
    const cls = {P0:"fh-p0",P1:"fh-p1",P2:"fh-p2",P3:"fh-p3"}[p] ?? "fh-p3";
    return `<div class="fault-header ${cls}"><span class="fh-badge">${esc(level)}</span><span class="fh-rest">${esc(rest)}</span></div>`;
  }

  // └─ / ├─ 树形说明行
  if (t.includes("└─") || t.includes("├─"))
    return `<p class="tree-note">${esc(t)}</p>`;

  // 普通 <p>
  return `<p class="plain">${esc(t)}</p>`;
}

/** 把 HTML 按 <br>/</p> 拆成行，保留标签结构 */
function htmlToTextLines(html) {
  return html
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n")
    .split("\n");
}

function esc(s) {
  return String(s)
    .replace(/&(?!amp;|lt;|gt;|quot;)/g,"&amp;")
    .replace(/</g,"&lt;").replace(/>/g,"&gt;");
}

// ══════════════════════════════════════════════════════════════════
// 3. 纯文本源文件检测 & 预处理
//    如果 MD 里大量使用空格对齐表格，先做 MD 级别转换再交给 marked
// ══════════════════════════════════════════════════════════════════

/**
 * 检测是否是「纯文本报告型」MD（包含 ===HEAVY=== 风格或大量 【】标题）
 */
function isPlainTextReport(md) {
  return (md.match(/【[^】]+】/g) || []).length > 3 ||
         md.includes("===HEAVY===") ||
         /^\s+\S+\s{3,}\S+\s{3,}\S+/m.test(md);
}

/**
 * 对纯文本报告型 MD 做预处理：
 * 1. ===HEAVY=== → ## 章节标题（取夹在两行之间的文本）
 * 2. 空格对齐表格（--- 分隔）→ GFM 表格
 * 3. 【标题】 → ### 标题
 */
function preprocessPlainText(md) {
  const lines = md.split("\n");
  const out   = [];
  let i = 0;

  while (i < lines.length) {
    const l = lines[i];

    // ── ===HEAVY=== 包裹的章节标题 ──────────────────────────────
    if (l.trim() === "===HEAVY===") {
      let j = i + 1;
      while (j < lines.length && !lines[j].trim()) j++;
      if (j < lines.length && lines[j].trim() !== "===HEAVY===") {
        const title = lines[j].trim();
        // skip the title line and trailing heavy hr
        let k = j + 1;
        while (k < lines.length && !lines[k].trim()) k++;
        if (k < lines.length && lines[k].trim() === "===HEAVY===") {
          out.push(`\n## ${title}\n`);
          i = k + 1; continue;
        }
      }
      out.push("---"); i++; continue;
    }

    // ── 空格对齐表格（两个 --- 之间） ───────────────────────────
    if (l.trim() === "---") {
      const result = tryConvertTable(lines, i);
      if (result) {
        out.push(result.md);
        i = result.next; continue;
      }
      out.push(""); i++; continue;
    }

    // ── 【标题】行 ───────────────────────────────────────────────
    const bm = l.trim().match(/^【([^】]+)】\s*(.*)$/);
    if (bm) {
      out.push(`\n### ${bm[1]}${bm[2] ? " " + bm[2] : ""}\n`);
      i++; continue;
    }

    out.push(l); i++;
  }
  return out.join("\n");
}

/**
 * 尝试把 --- header --- rows --- 转成 GFM 表格
 * 返回 {md, next} 或 null
 */
function tryConvertTable(lines, start) {
  if (lines[start].trim() !== "---") return null;

  // 找 header 行（紧接 --- 后的非空行）
  let hi = start + 1;
  while (hi < lines.length && !lines[hi].trim()) hi++;
  if (hi >= lines.length || lines[hi].trim() === "---") return null;

  const headerLine = lines[hi].trim();

  // 找第二个 ---
  let sep2 = hi + 1;
  while (sep2 < lines.length && lines[sep2].trim() !== "---") sep2++;
  if (sep2 >= lines.length) return null;

  // 收集数据行直到下一个 ---
  const dataLines = [];
  let ri = sep2 + 1;
  while (ri < lines.length && lines[ri].trim() !== "---" && lines[ri].trim() !== "===HEAVY===") {
    if (lines[ri].trim()) dataLines.push(lines[ri]);
    ri++;
  }

  // 解析列（≥2空格分隔）
  const splitCols = (l) => l.trim().split(/  +/).map(s=>s.trim()).filter(Boolean);
  const headers   = splitCols(headerLine);
  if (headers.length < 2) return null;

  const sep = "| " + headers.join(" | ") + " |";
  const div = "|" + headers.map(()=>" --- ").join("|") + "|";
  const rows = dataLines.map(dl => {
    const cols = splitCols(dl);
    while (cols.length < headers.length) cols.push("");
    return "| " + cols.slice(0, headers.length).join(" | ") + " |";
  });

  const tableMd = [sep, div, ...rows].join("\n");
  // skip trailing ---
  const next = lines[ri]?.trim() === "---" ? ri + 1 : ri;
  return { md: "\n" + tableMd + "\n", next };
}

// ══════════════════════════════════════════════════════════════════
// 4. 主流程
// ══════════════════════════════════════════════════════════════════
const isReport = isPlainTextReport(mdContent);
const processed = isReport ? preprocessPlainText(mdContent) : mdContent;

let bodyHTML = marked.parse(processed);

// 正文 <p> 不用等宽字体（修复旧版 bug）
bodyHTML = bodyHTML
  .replace(/font-family:\s*var\(--font-mono\)/g, "")
  .replace(/white-space:\s*pre-wrap/g, "");

// 对裸文本行做二次结构化
if (isReport) {
  bodyHTML = enrichReportHTML(bodyHTML);
}

function enrichReportHTML(html) {
  // badge 化 ✅ ❌ ⚠️ 在 <td> 和 <li> 里
  html = html.replace(/<td>(([^<]*)(✅|❌|⚠️|⚠)[^<]*)<\/td>/g, (_, inner) =>
    `<td>${badgeStatus(inner)}</td>`
  );
  // 全局警告行（在 <p> 里的）
  html = html.replace(/<p>([^<]*🔴[^<]*全局警告[^<]*)<\/p>/g,
    (_,t) => `<div class="global-warn">${t}</div>`);
  // └─ 树形说明
  html = html.replace(/<p>([^<]*[└├][─][^<]*)<\/p>/g,
    (_,t) => `<p class="tree-note">${t}</p>`);
  // 合并相邻 <ul>
  html = html.replace(/<\/ul>\s*<ul>/g, "");
  return html;
}

function badgeStatus(text) {
  const t = text.trim();
  if (t.includes("✅")) return `<span class="badge-ok">${t}</span>`;
  if (t.includes("❌")) return `<span class="badge-err">${t}</span>`;
  if (t.includes("⚠")) return `<span class="badge-warn">${t}</span>`;
  return t;
}

// ── 页面标题 ───────────────────────────────────────────────────────
const titleMatch = mdContent.match(/^#\s+(.+)/m) ||
                   mdContent.match(/服务器[^\n]{0,30}报告/);
const pageTitle  = titleMatch
  ? (titleMatch[1] || titleMatch[0]).replace(/[\u{1F300}-\u{1F9FF}]/gu,"").replace(/[*_`]/g,"").trim()
  : stem;

// ── TOC ────────────────────────────────────────────────────────────
function buildToc(items) {
  const filtered = items.filter(i => i.level <= 3);
  if (filtered.filter(i => i.level <= 2).length < 2) return "";
  return `<nav class="toc" id="toc">
  <div class="toc-title">目录</div>
  ${filtered.map(i=>`<a href="#${i.id}" class="toc-l${i.level}">${i.text}</a>`).join("\n  ")}
</nav>`;
}

const tocHTML = buildToc(tocItems);
const hasToc  = tocHTML.length > 0;
const genTime = new Date().toLocaleString("zh-CN",{year:"numeric",month:"2-digit",day:"2-digit",hour:"2-digit",minute:"2-digit"});

// ══════════════════════════════════════════════════════════════════
// 5. HTML 模板
// ══════════════════════════════════════════════════════════════════
const fullHTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${pageTitle}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Lora:ital,wght@0,400;0,600;1,400&family=Source+Sans+3:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
:root {
  --bg:#f8f7f4; --surface:#fff; --border:#e8e5df; --border-soft:#f0ede8;
  --text:#1c1917; --text-2:#57534e; --text-3:#a8a29e;
  --accent:#1d4e6e; --accent-light:#e8f1f7; --accent-mid:#3b82a0;
  --red:#c0392b; --red-bg:#fef2f2;
  --amber:#92400e; --amber-bg:#fffbeb;
  --green:#14532d; --green-bg:#f0fdf4;
  --code-bg:#1a1d27; --code-text:#cdd6f4; --code-border:#2d3148;
  --font-body:"Source Sans 3","PingFang SC","Hiragino Sans GB",sans-serif;
  --font-head:"Lora","PingFang SC",Georgia,serif;
  --font-mono:"JetBrains Mono","Fira Code",Consolas,monospace;
  --radius:8px; --radius-lg:12px;
  --shadow:0 1px 3px rgba(0,0,0,.06),0 4px 16px rgba(0,0,0,.05);
  --shadow-lg:0 2px 8px rgba(0,0,0,.07),0 8px 32px rgba(0,0,0,.06);
  --toc-width:240px; --gap:32px;
}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html{font-size:16px;scroll-behavior:smooth}
body{font-family:var(--font-body);background:var(--bg);color:var(--text);line-height:1.8;-webkit-font-smoothing:antialiased}
#progress{position:fixed;top:0;left:0;height:3px;width:0%;background:linear-gradient(90deg,var(--accent-mid),var(--accent));z-index:999;transition:width .1s linear;border-radius:0 2px 2px 0}
.layout{display:flex;align-items:flex-start;max-width:calc(var(--toc-width) + 820px + var(--gap)*3);margin:0 auto;padding:48px var(--gap) 96px;gap:var(--gap)}
/* TOC */
.toc{width:var(--toc-width);flex-shrink:0;position:sticky;top:32px;max-height:calc(100vh - 64px);overflow-y:auto;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);padding:20px;box-shadow:var(--shadow);scrollbar-width:thin}
.toc-title{font-size:10.5px;font-weight:600;letter-spacing:.1em;text-transform:uppercase;color:var(--text-3);margin-bottom:12px;padding-bottom:10px;border-bottom:1px solid var(--border-soft)}
.toc a{display:block;font-size:13px;color:var(--text-2);text-decoration:none;padding:4px 8px;border-radius:5px;line-height:1.45;transition:background .15s,color .15s;word-break:break-all}
.toc a:hover,.toc a.active{background:var(--accent-light);color:var(--accent);font-weight:500}
.toc-l1{font-weight:600;color:var(--text)}
.toc-l2{font-weight:600;color:var(--text)}
.toc-l3{padding-left:14px!important;font-size:12px!important}
/* Article */
.article{flex:1;min-width:0;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius-lg);padding:52px 60px;box-shadow:var(--shadow-lg)}
/* Headings */
.article h1{font-family:var(--font-head);font-size:26px;font-weight:600;line-height:1.3;margin:0 0 28px;padding-bottom:18px;border-bottom:2px solid var(--text)}
.article h2{font-family:var(--font-head);font-size:19px;font-weight:600;margin:48px 0 14px;padding-bottom:8px;border-bottom:1px solid var(--border)}
.article h2::before{content:attr(data-index);display:inline-block;font-family:var(--font-mono);font-size:10.5px;font-weight:500;color:var(--accent-mid);background:var(--accent-light);padding:1px 7px;border-radius:4px;margin-right:10px;vertical-align:middle;letter-spacing:.05em}
.article h3{font-family:var(--font-head);font-size:15.5px;font-weight:600;margin:28px 0 10px}
.article h3::before{content:"§ ";color:var(--text-3);font-family:var(--font-mono);font-size:13px}
.article h4{font-size:13.5px;font-weight:600;color:var(--accent);margin:20px 0 8px}
/* Body */
.article p,.plain{font-size:15px;line-height:1.85;color:var(--text);margin:0 0 12px;font-family:var(--font-body)}
.article strong{font-weight:600}
.article em{font-style:italic;color:var(--text-2)}
.article a{color:var(--accent);text-decoration:underline;text-decoration-color:var(--accent-light);text-underline-offset:3px}
.article a:hover{text-decoration-color:var(--accent)}
.article hr{border:none;border-top:1px solid var(--border);margin:20px 0}
.article ul,.article ol{padding-left:22px;margin:6px 0 14px}
.article li{font-size:15px;line-height:1.8;margin:4px 0}
.article li::marker{color:var(--accent-mid)}
.article :not(pre)>code{font-family:var(--font-mono);font-size:12.5px;font-weight:500;background:#f3f0eb;color:var(--red);padding:1px 5px;border-radius:4px;border:1px solid var(--border)}
/* Code blocks */
.code-block{position:relative;margin:20px 0;border-radius:var(--radius-lg);overflow:hidden;border:1px solid var(--code-border);box-shadow:0 4px 20px rgba(0,0,0,.16)}
.code-lang{position:absolute;top:0;left:0;font-family:var(--font-mono);font-size:10px;font-weight:500;color:#7c8db5;background:#222538;padding:4px 12px;border-bottom-right-radius:6px;text-transform:uppercase;letter-spacing:.08em;user-select:none}
.copy-btn{position:absolute;top:8px;right:10px;background:#2d3148;border:1px solid #3d4260;border-radius:5px;color:#7c8db5;cursor:pointer;padding:5px 8px;display:flex;align-items:center;transition:background .15s,color .15s;z-index:1}
.copy-btn:hover{background:#3a3f60;color:#cdd6f4}
.copy-btn.copied{color:#a6e3a1;border-color:#4a6a4a}
.code-block pre{margin:0;padding:36px 20px 20px;background:var(--code-bg);overflow-x:auto;scrollbar-width:thin;scrollbar-color:#3d4260 transparent}
.code-block pre::-webkit-scrollbar{height:5px}
.code-block pre::-webkit-scrollbar-thumb{background:#3d4260;border-radius:3px}
.code-block code{font-family:var(--font-mono);font-size:13px;line-height:1.7;color:var(--code-text);background:none;border:none;padding:0;white-space:pre;word-break:normal}
/* Tables */
.table-wrap{overflow-x:auto;margin:16px 0;border-radius:var(--radius-lg);border:1px solid var(--border);box-shadow:var(--shadow)}
table{width:100%;border-collapse:collapse;font-size:14px;min-width:360px}
thead{background:#f4f2ee}
th{padding:9px 14px;text-align:left;font-size:11.5px;font-weight:600;letter-spacing:.04em;text-transform:uppercase;color:var(--text-2);border-bottom:1px solid var(--border);white-space:nowrap}
td{padding:8px 14px;border-bottom:1px solid var(--border-soft);color:var(--text);vertical-align:top;line-height:1.6}
tbody tr:last-child td{border-bottom:none}
tbody tr:nth-child(even) td{background:#faf9f7}
tbody tr:hover td{background:var(--accent-light);transition:background .1s}
/* KV block */
.kv-block{background:var(--bg);border:1px solid var(--border);border-radius:var(--radius-lg);overflow:hidden;margin:12px 0 20px}
.kv-row{display:flex;border-bottom:1px solid var(--border-soft);align-items:flex-start}
.kv-row:last-child{border-bottom:none}
.kv-key{flex:0 0 160px;padding:9px 16px;font-size:13.5px;font-weight:600;color:var(--text-2);background:var(--surface);border-right:1px solid var(--border-soft)}
.kv-val{flex:1;padding:9px 16px;font-size:14px;color:var(--text)}
/* Status badges */
.badge-ok{display:inline-flex;align-items:center;gap:4px;background:var(--green-bg);color:var(--green);font-size:13px;font-weight:500;padding:2px 9px;border-radius:20px;border:1px solid #bbf7d0}
.badge-err{display:inline-flex;align-items:center;gap:4px;background:var(--red-bg);color:var(--red);font-size:13px;font-weight:500;padding:2px 9px;border-radius:20px;border:1px solid #fecaca}
.badge-warn{display:inline-flex;align-items:center;gap:4px;background:var(--amber-bg);color:var(--amber);font-size:13px;font-weight:500;padding:2px 9px;border-radius:20px;border:1px solid #fde68a}
/* Priority badges */
.pri-p0{display:inline-block;background:#fef2f2;color:#991b1b;border:1px solid #fca5a5;font-size:12px;font-weight:700;padding:2px 8px;border-radius:4px;letter-spacing:.04em}
.pri-p1{display:inline-block;background:#fff7ed;color:#9a3412;border:1px solid #fdba74;font-size:12px;font-weight:700;padding:2px 8px;border-radius:4px}
.pri-p2{display:inline-block;background:#fffbeb;color:#92400e;border:1px solid #fde68a;font-size:12px;font-weight:700;padding:2px 8px;border-radius:4px}
.pri-p3{display:inline-block;background:var(--accent-light);color:var(--accent);border:1px solid #bfdbfe;font-size:12px;font-weight:700;padding:2px 8px;border-radius:4px}
/* Fault header */
.fault-header{display:flex;align-items:center;gap:12px;padding:12px 16px;border-radius:var(--radius-lg);margin:16px 0 8px;border:1px solid}
.fh-p0{background:#fef2f2;border-color:#fca5a5}
.fh-p1{background:#fff7ed;border-color:#fdba74}
.fh-p2{background:#fffbeb;border-color:#fde68a}
.fh-p3{background:var(--accent-light);border-color:#bfdbfe}
.fh-badge{font-family:var(--font-mono);font-size:11px;font-weight:700;letter-spacing:.08em}
.fh-p0 .fh-badge{color:#991b1b}.fh-p1 .fh-badge{color:#9a3412}.fh-p2 .fh-badge{color:#92400e}.fh-p3 .fh-badge{color:var(--accent)}
.fh-rest{font-size:14px;font-weight:500;color:var(--text)}
/* Timeline */
.timeline{border-left:2px solid var(--accent-mid);margin:16px 0 16px 8px;padding-left:20px}
.tl-row{display:flex;align-items:baseline;gap:10px;margin:8px 0;font-size:13.5px}
.tl-ts{font-family:var(--font-mono);font-size:12px;color:var(--text-3);flex-shrink:0;white-space:nowrap}
.tl-tag{font-size:11px;font-weight:600;padding:1px 7px;border-radius:10px;flex-shrink:0;background:var(--accent-light);color:var(--accent)}
.tl-tag.err{background:var(--red-bg);color:var(--red)}
.tl-tag.warn{background:var(--amber-bg);color:var(--amber)}
.tl-desc{color:var(--text);line-height:1.5}
/* Global warn */
.global-warn{background:#fef2f2;border:1px solid #fca5a5;border-radius:var(--radius-lg);padding:14px 18px;font-size:14.5px;font-weight:600;color:#991b1b;margin:16px 0}
/* Tree note */
.tree-note{font-family:var(--font-mono);font-size:12.5px;color:var(--text-2);padding:3px 0 3px 16px;border-left:2px solid var(--border-soft);margin:3px 0 3px 8px}
/* Disclaimer */
.disclaimer{background:var(--bg);border:1px solid var(--border);border-radius:var(--radius);padding:14px 18px;font-size:13.5px;color:var(--text-2);font-style:italic}
/* Meta */
.meta{margin-top:48px;padding-top:16px;border-top:1px solid var(--border-soft);display:flex;justify-content:space-between;align-items:center;font-size:12px;color:var(--text-3)}
.meta-source{font-family:var(--font-mono);font-size:11.5px}
/* Print */
@media print{body{background:white}#progress,.toc{display:none}.layout{display:block;padding:0}.article{border:none;box-shadow:none;padding:24px}.copy-btn{display:none}}
/* Responsive */
@media(max-width:900px){.toc{display:none}.article{padding:36px 28px}.layout{padding:24px 16px 64px}}
@media(max-width:480px){.article{padding:24px 18px}.article h1{font-size:22px}}
</style>
</head>
<body>
<div id="progress"></div>
<div class="layout">
  ${hasToc ? tocHTML : ""}
  <article class="article" id="article">
    ${bodyHTML}
    <div class="meta">
      <span class="meta-source">${stem}.md</span>
      <span>生成于 ${genTime}</span>
    </div>
  </article>
</div>
<script>
window.addEventListener("scroll",()=>{
  const el=document.documentElement;
  const pct=el.scrollTop/(el.scrollHeight-el.clientHeight)*100;
  document.getElementById("progress").style.width=Math.min(pct,100)+"%";
});
(function(){
  const headings=Array.from(document.querySelectorAll("article h1,article h2,article h3"));
  const links=Array.from(document.querySelectorAll(".toc a"));
  if(!links.length)return;
  const obs=new IntersectionObserver(entries=>{
    entries.forEach(e=>{
      if(!e.isIntersecting)return;
      links.forEach(l=>l.classList.remove("active"));
      const a=links.find(l=>l.getAttribute("href")==="#"+e.target.id);
      if(a)a.classList.add("active");
    });
  },{rootMargin:"-10% 0px -80% 0px"});
  headings.forEach(h=>obs.observe(h));
})();
(function(){
  let idx=0;
  document.querySelectorAll("article h2").forEach(el=>{
    idx++;
    el.setAttribute("data-index",String(idx).padStart(2,"0"));
  });
})();
function copyCode(btn){
  const code=btn.closest(".code-block").querySelector("code").innerText;
  navigator.clipboard.writeText(code).then(()=>{
    btn.classList.add("copied");
    btn.innerHTML='<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>';
    setTimeout(()=>{
      btn.classList.remove("copied");
      btn.innerHTML='<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>';
    },2000);
  });
}
</script>
</body>
</html>`;

// ── 写出 ───────────────────────────────────────────────────────────
try {
  writeFileSync(outputPath, fullHTML, "utf-8");
  console.log("✅ 转换成功");
  console.log(`   输入: ${inputPath}`);
  console.log(`   输出: ${outputPath}`);
} catch (e) {
  console.error(`❌ 写出失败: ${outputPath}\n${e.message}`);
  process.exit(1);
}
