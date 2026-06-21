import type { Report, ReportBlock } from "../types";

/** 把结构化报告导出为可独立打开的 HTML 文件（FR-012「下载 HTML」）。
 *  真实实现中后端已保存 baize 渲染的 .html，可直接下载；此处由前端结构生成等价文档。 */

function esc(s: string): string {
  return s.replace(/[&<>]/g, (m) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[m] as string);
}

function block(b: ReportBlock): string {
  switch (b.t) {
    case "kv":
      return `<table><tbody>${b.rows.map((r) => `<tr><td class="k">${esc(r[0])}</td><td>${r[1]}</td></tr>`).join("")}</tbody></table>`;
    case "table":
      return `<table><thead><tr>${b.head.map((h) => `<th>${esc(h)}</th>`).join("")}</tr></thead><tbody>${b.rows.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join("")}</tr>`).join("")}</tbody></table>`;
    case "p":
      return `<p>${b.html}</p>`;
    case "ul":
      return `<ul>${b.items.map((i) => `<li>${i}</li>`).join("")}</ul>`;
    case "ol":
      return `<ol>${b.items.map((i) => `<li>${i}</li>`).join("")}</ol>`;
    case "code":
      return `<pre>${esc(b.text)}</pre>`;
    case "tone":
      return `<div class="tone ${b.tone}">${b.html}</div>`;
    case "chain":
      return `<p>${b.nodes.map((n) => (n.bad ? `<b>${esc(n.text)}</b>` : esc(n.text))).join(" → ")}</p>`;
    case "timeline":
      return `<ul>${b.items.map((i) => `<li><code>${esc(i.time)}</code> ${esc(i.text)}</li>`).join("")}</ul>`;
    case "sub":
      return `<h4>${esc(b.title)}</h4>${b.blocks.map(block).join("")}`;
    default:
      return "";
  }
}

export function buildReportHtml(report: Report): string {
  const m = report.meta;
  const body = report.sections
    .map((s) => `<section><h3>${esc(s.label)}</h3>${s.blocks.map(block).join("")}</section>`)
    .join("");
  return `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"><title>故障诊断报告 ${esc(m.id)}</title>
<style>
body{font-family:Georgia,"Noto Serif SC",serif;max-width:880px;margin:40px auto;padding:0 24px;color:#1b2430;line-height:1.7}
h2{border-bottom:2.5px solid #1b2430;padding-bottom:12px}
h3{font-size:21px;margin-top:34px}
.meta{background:#eef4fb;border-radius:10px;padding:16px 20px;margin:20px 0}
table{width:100%;border-collapse:collapse;margin:10px 0;font-family:sans-serif;font-size:14px}
th,td{border:1px solid #e2e8f0;padding:9px 12px;text-align:left;vertical-align:top}
td.k{width:120px;background:#fafbfd;font-weight:600}
pre{background:#0f1822;color:#9fd0c8;padding:13px 15px;border-radius:9px;overflow:auto;font-size:12px}
.tone{border-radius:9px;padding:12px 15px;margin:10px 0;font-family:sans-serif;font-size:13px}
.tone.info{background:#e3f4f1}.tone.warn{background:#fdf3df}.tone.ok{background:#e6f5ec}.tone.danger{background:#fbe9e9}
.hl{background:#fbe9e9;color:#c0392b;padding:1px 6px;border-radius:4px;font-family:monospace;font-size:12px}
.ok-hl{background:#e6f5ec;color:#0f7a3d;padding:1px 6px;border-radius:4px;font-family:monospace;font-size:12px}
</style></head><body>
<h2>故障诊断报告</h2>
<div class="meta">
<div><b>报告编号：</b>${esc(m.id)}</div>
<div><b>故障级别：</b>${esc(m.level)}</div>
<div><b>报告时间：</b>${esc(m.time)}</div>
<div><b>当前状态：</b>${esc(m.status)}</div>
<div><b>by：</b>${esc(m.agent)}</div>
</div>
${body}
</body></html>`;
}

export function downloadReportHtml(report: Report): void {
  const html = buildReportHtml(report);
  const blob = new Blob([html], { type: "text/html;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `${report.meta.id}.html`;
  a.click();
  URL.revokeObjectURL(url);
}
