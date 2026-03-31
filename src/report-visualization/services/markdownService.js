const { marked } = require('marked');
const hljs = require('highlight.js');

// 配置 marked：启用代码高亮
marked.setOptions({
  highlight(code, lang) {
    const language = hljs.getLanguage(lang) ? lang : 'plaintext';
    return hljs.highlight(code, { language }).value;
  },
  langPrefix: 'hljs language-',
  gfm: true,        // 支持 GitHub Flavored Markdown
  breaks: true,     // 换行符转 <br>
});

/**
 * 将 Markdown 文本转换为完整 HTML 页面
 * @param {string} markdown   - 原始 MD 内容
 * @param {string} title      - 报告标题（用于 <title> 标签）
 * @returns {string}          - 完整 HTML 字符串
 */
function toHtml(markdown, title = '故障诊断报告') {
  const body = marked.parse(markdown);
  return buildHtmlTemplate(body, title);
}

/**
 * 构建完整 HTML 模板（注入样式、代码高亮 CSS）
 */
function buildHtmlTemplate(body, title) {
  // highlight.js 样式使用 CDN，也可改为内联 CSS
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(title)}</title>
  <link rel="stylesheet"
    href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">
  <style>
    /* ── 整体布局 ── */
    *, *::before, *::after { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      font-size: 15px;
      line-height: 1.7;
      color: #24292e;
      background: #f6f8fa;
      margin: 0;
      padding: 24px 16px;
    }
    .report-container {
      max-width: 860px;
      margin: 0 auto;
      background: #fff;
      border: 1px solid #d0d7de;
      border-radius: 8px;
      padding: 40px 48px;
    }

    /* ── 报告头部 ── */
    .report-header {
      border-bottom: 2px solid #e1e4e8;
      padding-bottom: 16px;
      margin-bottom: 32px;
    }
    .report-header h1 { margin: 0 0 6px; font-size: 22px; color: #1f2328; }
    .report-meta { font-size: 13px; color: #57606a; }

    /* ── Markdown 内容样式 ── */
    h1, h2, h3, h4 { font-weight: 600; line-height: 1.3; margin: 24px 0 12px; color: #1f2328; }
    h2 { font-size: 18px; border-bottom: 1px solid #e1e4e8; padding-bottom: 8px; }
    h3 { font-size: 16px; }
    p  { margin: 0 0 14px; }
    a  { color: #0969da; text-decoration: none; }
    a:hover { text-decoration: underline; }

    /* ── 代码块 ── */
    pre {
      background: #f6f8fa;
      border: 1px solid #d0d7de;
      border-radius: 6px;
      padding: 14px 16px;
      overflow-x: auto;
      font-size: 13px;
      line-height: 1.5;
      margin: 16px 0;
    }
    code {
      font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', monospace;
      font-size: 13px;
    }
    :not(pre) > code {
      background: #f0f0f0;
      border-radius: 4px;
      padding: 2px 6px;
      color: #d73a49;
    }

    /* ── 表格 ── */
    table { border-collapse: collapse; width: 100%; margin: 16px 0; }
    th, td { border: 1px solid #d0d7de; padding: 8px 12px; text-align: left; }
    th { background: #f6f8fa; font-weight: 600; }
    tr:nth-child(even) td { background: #fafafa; }

    /* ── 引用块 ── */
    blockquote {
      border-left: 4px solid #d0d7de;
      margin: 16px 0;
      padding: 4px 16px;
      color: #57606a;
    }

    /* ── 严重性标签（故障报告常用） ── */
    .badge {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 12px;
      font-size: 12px;
      font-weight: 600;
    }
    .badge-critical { background: #ffd6d6; color: #a10000; }
    .badge-warning  { background: #fff3cd; color: #7a5800; }
    .badge-info     { background: #dce8ff; color: #0550ae; }

    /* ── 打印优化 ── */
    @media print {
      body { background: #fff; padding: 0; }
      .report-container { border: none; padding: 0; }
    }
  </style>
</head>
<body>
  <div class="report-container">
    <div class="report-header">
      <h1>${escapeHtml(title)}</h1>
      <div class="report-meta">
        生成时间：${new Date().toLocaleString('zh-CN')}
      </div>
    </div>
    <div class="report-content">
      ${body}
    </div>
  </div>
</body>
</html>`;
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

module.exports = { toHtml };
