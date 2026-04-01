# 故障诊断报告服务 — 技术设计文档

> 语言：Node.js（JavaScript）  
> 接口风格：RESTful API  
> 报告格式：Markdown → HTML  
> 版本：v1.0

---

## 目录

1. [系统概述](#1-系统概述)
2. [技术选型](#2-技术选型)
3. [项目结构](#3-项目结构)
4. [核心流程设计](#4-核心流程设计)
5. [Markdown 转 HTML 方案](#5-markdown-转-html-方案)
6. [REST API 接口设计](#6-rest-api-接口设计)
7. [数据库设计](#7-数据库设计)
8. [存储设计](#8-存储设计)
9. [服务启动方案](#9-服务启动方案)
10. [安全设计](#10-安全设计)
11. [错误处理规范](#11-错误处理规范)
12. [部署方案](#12-部署方案)

---

## 1. 系统概述

### 1.1 功能目标

故障诊断系统完成分析后，将结果以 Markdown 文档的形式生成报告，并通过 REST API 对外提供访问能力。用户通过返回的唯一链接，可在浏览器中查看渲染后的 HTML 报告。

### 1.2 核心流程

```
故障系统触发
    → POST /api/reports          # 创建报告（上传 MD 内容）
    → 服务生成 UUID，MD 转 HTML
    → 存储到文件系统 / 对象存储
    → 返回报告链接
         ↓
用户访问链接
    → GET /api/reports/:id        # 读取报告
    → 返回 HTML 内容（浏览器直接渲染）
```

---

## 2. 技术选型

| 模块 | 选型 | 说明 |
|------|------|------|
| Web 框架 | **Express.js** | 轻量、生态成熟，适合 REST API |
| MD → HTML | **marked** + **highlight.js** | marked 负责转换，highlight.js 提供代码高亮 |
| HTML 模板 | **内联模板字符串** | 无需模板引擎，轻量可控 |
| 唯一 ID | **nanoid** | 比 UUID 更短，URL 友好，`rpt_abc123` 格式 |
| 数据库 | **better-sqlite3**（单机）/ **PostgreSQL**（分布式） | 存元数据；小规模用 SQLite，生产用 PG |
| 文件存储 | **本地 fs**（单机）/ **AWS S3**（生产） | 存 MD 原文 + HTML 渲染结果 |
| 进程管理 | **PM2** | 生产环境守护进程、日志、重启 |
| 环境变量 | **dotenv** | 管理配置 |

---

## 3. 项目结构

```
report-service/
├── src/
│   ├── app.js                  # Express 应用入口
│   ├── server.js               # 启动入口（监听端口）
│   ├── config/
│   │   └── index.js            # 统一配置（读取环境变量）
│   ├── routes/
│   │   └── reports.js          # /api/reports 路由定义
│   ├── controllers/
│   │   └── reportController.js # 业务逻辑控制器
│   ├── services/
│   │   ├── reportService.js    # 报告生成、查询核心逻辑
│   │   ├── markdownService.js  # MD → HTML 转换
│   │   └── storageService.js   # 文件读写（本地 or S3）
│   ├── models/
│   │   └── reportModel.js      # 数据库操作（元数据）
│   ├── middlewares/
│   │   ├── errorHandler.js     # 全局错误处理
│   │   └── auth.js             # API Key 校验（可选）
│   └── utils/
│       └── idGenerator.js      # 生成 NanoID
├── storage/                    # 本地存储目录（.gitignore）
│   ├── markdown/               # 原始 MD 文件
│   └── html/                   # 渲染后 HTML 文件
├── .env                        # 环境变量（不提交）
├── .env.example                # 环境变量模板
├── package.json
└── ecosystem.config.js         # PM2 配置
```

---

## 4. 核心流程设计

### 4.1 报告创建流程

```
POST /api/reports
  │
  ├─ 1. 校验请求参数（title, content 必填）
  ├─ 2. 生成 reportId = nanoid()  →  rpt_7xKq2m9z
  ├─ 3. markdownService.toHtml(content)
  │       └─ marked.parse(md) + highlight.js 代码高亮
  │           └─ 注入 HTML 模板（head + 样式）
  ├─ 4. storageService.save(reportId, { md, html })
  │       ├─ 写 storage/markdown/{reportId}.md
  │       └─ 写 storage/html/{reportId}.html
  ├─ 5. reportModel.insert({ reportId, title, createdAt, expiresAt })
  └─ 6. 返回 { id, url, expiresAt }
```

### 4.2 报告访问流程

```
GET /api/reports/:id
  │
  ├─ 1. reportModel.findById(id)
  │       ├─ 不存在 → 404
  │       └─ 已过期 → 410 Gone
  ├─ 2. storageService.readHtml(id)
  └─ 3. res.setHeader('Content-Type', 'text/html')
         res.send(htmlContent)
         → 浏览器直接渲染报告页面
```

---

## 5. Markdown 转 HTML 方案

### 5.1 依赖安装

```bash
npm install marked highlight.js
```

### 5.2 markdownService.js 实现

```javascript
// src/services/markdownService.js

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
```

### 5.3 转换效果说明

| Markdown 语法 | 转换结果 |
|--------------|--------|
| `# 标题` | `<h1>` 带下划线样式 |
| ` ```python ` | 带语法高亮的 `<pre><code>` |
| `| 表头 |` | 带交替行色的 `<table>` |
| `> 引用` | 左侧蓝色竖线的 `<blockquote>` |
| `**粗体**` | `<strong>` |

---

## 6. REST API 接口设计

### 6.1 接口总览

| Method | Path | 描述 |
|--------|------|------|
| `POST` | `/api/reports` | 创建报告 |
| `GET` | `/api/reports/:id` | 获取报告（HTML 页面） |
| `GET` | `/api/reports/:id/meta` | 获取报告元数据（JSON） |
| `DELETE` | `/api/reports/:id` | 删除报告 |
| `GET` | `/api/health` | 健康检查 |

---

### 6.2 POST `/api/reports` — 创建报告

**Request**

```http
POST /api/reports
Content-Type: application/json
X-API-Key: your-api-key          # 可选：内部调用鉴权

{
  "title": "2024-03-28 数据库连接池耗尽故障报告",
  "content": "# 故障摘要\n\n## 影响范围\n...",
  "expiresInDays": 30,           # 可选，默认 30 天
  "metadata": {                  # 可选，业务附加信息
    "severity": "critical",
    "service": "order-service",
    "incidentId": "INC-2024-001"
  }
}
```

**Response 201 Created**

```json
{
  "success": true,
  "data": {
    "id": "rpt_7xKq2m9z",
    "title": "2024-03-28 数据库连接池耗尽故障报告",
    "url": "https://your-domain.com/api/reports/rpt_7xKq2m9z",
    "expiresAt": "2024-04-27T08:00:00.000Z",
    "createdAt": "2024-03-28T08:00:00.000Z"
  }
}
```

---

### 6.3 GET `/api/reports/:id` — 查看报告

```http
GET /api/reports/rpt_7xKq2m9z
Accept: text/html
```

**Response 200 OK** — 直接返回 HTML，浏览器渲染报告页面

```http
Content-Type: text/html; charset=utf-8
X-Report-Id: rpt_7xKq2m9z
X-Expires-At: 2024-04-27T08:00:00.000Z

<!DOCTYPE html>...
```

**异常响应**

| 状态码 | 场景 |
|--------|------|
| `404 Not Found` | 报告 ID 不存在 |
| `410 Gone` | 报告已过期 |
| `403 Forbidden` | 无权访问（需要 token） |

---

### 6.4 GET `/api/reports/:id/meta` — 获取元数据

```http
GET /api/reports/rpt_7xKq2m9z/meta
```

```json
{
  "success": true,
  "data": {
    "id": "rpt_7xKq2m9z",
    "title": "2024-03-28 数据库连接池耗尽故障报告",
    "createdAt": "2024-03-28T08:00:00.000Z",
    "expiresAt": "2024-04-27T08:00:00.000Z",
    "metadata": { "severity": "critical", "service": "order-service" }
  }
}
```

---

### 6.5 路由实现

```javascript
// src/routes/reports.js

const express = require('express');
const router = express.Router();
const controller = require('../controllers/reportController');
const { authMiddleware } = require('../middlewares/auth');

// 创建报告需要鉴权（内部服务调用）
router.post('/', authMiddleware, controller.create);

// 查看报告公开访问（通过 ID 的不可猜测性保证安全）
router.get('/:id', controller.view);
router.get('/:id/meta', controller.meta);

// 删除报告需要鉴权
router.delete('/:id', authMiddleware, controller.remove);

module.exports = router;
```

```javascript
// src/controllers/reportController.js

const reportService = require('../services/reportService');

const create = async (req, res, next) => {
  try {
    const { title, content, expiresInDays = 30, metadata = {} } = req.body;

    if (!title || !content) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'title 和 content 为必填项' }
      });
    }

    const report = await reportService.createReport({ title, content, expiresInDays, metadata });

    res.status(201).json({ success: true, data: report });
  } catch (err) {
    next(err);
  }
};

const view = async (req, res, next) => {
  try {
    const { id } = req.params;
    const { html, meta } = await reportService.getReport(id);

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('X-Report-Id', id);
    res.setHeader('X-Expires-At', meta.expiresAt);
    // 缓存 1 小时（报告内容不变）
    res.setHeader('Cache-Control', 'public, max-age=3600');
    res.send(html);
  } catch (err) {
    next(err);
  }
};

const meta = async (req, res, next) => {
  try {
    const { id } = req.params;
    const data = await reportService.getReportMeta(id);
    res.json({ success: true, data });
  } catch (err) {
    next(err);
  }
};

const remove = async (req, res, next) => {
  try {
    await reportService.deleteReport(req.params.id);
    res.status(204).send();
  } catch (err) {
    next(err);
  }
};

module.exports = { create, view, meta, remove };
```

---

## 7. 数据库设计

### 7.1 报告元数据表 `reports`

```sql
CREATE TABLE reports (
  id           TEXT PRIMARY KEY,          -- NanoID，如 rpt_7xKq2m9z
  title        TEXT NOT NULL,
  md_path      TEXT NOT NULL,             -- MD 文件路径 or S3 key
  html_path    TEXT NOT NULL,             -- HTML 文件路径 or S3 key
  metadata     TEXT DEFAULT '{}',        -- JSON 字符串（业务附加信息）
  created_at   DATETIME DEFAULT CURRENT_TIMESTAMP,
  expires_at   DATETIME NOT NULL,
  deleted_at   DATETIME                  -- 软删除
);

-- 过期查询索引
CREATE INDEX idx_reports_expires ON reports(expires_at);
```

### 7.2 reportModel.js（SQLite 版）

```javascript
// src/models/reportModel.js

const Database = require('better-sqlite3');
const path = require('path');
const config = require('../config');

const db = new Database(path.join(config.dataDir, 'reports.db'));

// 初始化表
db.exec(`
  CREATE TABLE IF NOT EXISTS reports (
    id         TEXT PRIMARY KEY,
    title      TEXT NOT NULL,
    md_path    TEXT NOT NULL,
    html_path  TEXT NOT NULL,
    metadata   TEXT DEFAULT '{}',
    created_at TEXT DEFAULT (datetime('now')),
    expires_at TEXT NOT NULL,
    deleted_at TEXT
  );
  CREATE INDEX IF NOT EXISTS idx_reports_expires ON reports(expires_at);
`);

const insert = (report) => {
  const stmt = db.prepare(`
    INSERT INTO reports (id, title, md_path, html_path, metadata, expires_at)
    VALUES (@id, @title, @md_path, @html_path, @metadata, @expires_at)
  `);
  return stmt.run({
    ...report,
    metadata: JSON.stringify(report.metadata || {})
  });
};

const findById = (id) => {
  const row = db.prepare(
    `SELECT * FROM reports WHERE id = ? AND deleted_at IS NULL`
  ).get(id);
  if (row) row.metadata = JSON.parse(row.metadata);
  return row;
};

const softDelete = (id) => {
  return db.prepare(
    `UPDATE reports SET deleted_at = datetime('now') WHERE id = ?`
  ).run(id);
};

module.exports = { insert, findById, softDelete };
```

---

## 8. 存储设计

### 8.1 本地文件存储（开发 / 单机部署）

```javascript
// src/services/storageService.js

const fs = require('fs').promises;
const path = require('path');
const config = require('../config');

const mdDir   = path.join(config.storageDir, 'markdown');
const htmlDir = path.join(config.storageDir, 'html');

// 初始化目录
async function init() {
  await fs.mkdir(mdDir, { recursive: true });
  await fs.mkdir(htmlDir, { recursive: true });
}

async function save(id, { markdown, html }) {
  await Promise.all([
    fs.writeFile(path.join(mdDir,   `${id}.md`),   markdown, 'utf-8'),
    fs.writeFile(path.join(htmlDir, `${id}.html`), html,     'utf-8'),
  ]);
}

async function readHtml(id) {
  const filePath = path.join(htmlDir, `${id}.html`);
  return fs.readFile(filePath, 'utf-8');
}

async function remove(id) {
  await Promise.allSettled([
    fs.unlink(path.join(mdDir,   `${id}.md`)),
    fs.unlink(path.join(htmlDir, `${id}.html`)),
  ]);
}

module.exports = { init, save, readHtml, remove };
```

### 8.2 切换 S3 存储（生产环境）

只需替换 `storageService.js` 的实现，接口保持不变：

```javascript
// 生产环境替换为 S3 实现
const { S3Client, PutObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');

const s3 = new S3Client({ region: process.env.AWS_REGION });
const BUCKET = process.env.S3_BUCKET;

async function save(id, { markdown, html }) {
  await Promise.all([
    s3.send(new PutObjectCommand({
      Bucket: BUCKET, Key: `markdown/${id}.md`,
      Body: markdown, ContentType: 'text/markdown'
    })),
    s3.send(new PutObjectCommand({
      Bucket: BUCKET, Key: `html/${id}.html`,
      Body: html, ContentType: 'text/html'
    })),
  ]);
}

async function readHtml(id) {
  const res = await s3.send(new GetObjectCommand({
    Bucket: BUCKET, Key: `html/${id}.html`
  }));
  return res.Body.transformToString();
}
```

---

## 9. 服务启动方案

### 9.1 入口文件

```javascript
// src/app.js — Express 应用配置

const express = require('express');
const app = express();

app.use(express.json({ limit: '10mb' }));  // MD 文档可能较大

// 路由
app.use('/api/reports', require('./routes/reports'));
app.get('/api/health', (req, res) => res.json({ status: 'ok', ts: Date.now() }));

// 全局错误处理（必须放最后）
app.use(require('./middlewares/errorHandler'));

module.exports = app;
```

```javascript
// src/server.js — 启动监听

require('dotenv').config();
const app = require('./app');
const storage = require('./services/storageService');
const config = require('./config');

async function start() {
  // 初始化存储目录
  await storage.init();

  app.listen(config.port, () => {
    console.log(`[report-service] 服务启动成功`);
    console.log(`[report-service] 监听端口: ${config.port}`);
    console.log(`[report-service] 环境: ${config.nodeEnv}`);
  });
}

start().catch(err => {
  console.error('[report-service] 启动失败:', err);
  process.exit(1);
});
```

```javascript
// src/config/index.js — 统一配置

module.exports = {
  port:        process.env.PORT       || 3000,
  nodeEnv:     process.env.NODE_ENV   || 'development',
  apiKey:      process.env.API_KEY    || '',           // 鉴权 Key
  baseUrl:     process.env.BASE_URL   || 'http://localhost:3000',
  storageDir:  process.env.STORAGE_DIR || './storage',
  dataDir:     process.env.DATA_DIR    || './data',
};
```

### 9.2 环境变量配置

```bash
# .env.example

PORT=3000
NODE_ENV=production
API_KEY=your-secret-api-key-here
BASE_URL=https://reports.your-domain.com

# 存储配置（本地模式）
STORAGE_DIR=./storage
DATA_DIR=./data

# S3 配置（生产模式，二选一）
# AWS_REGION=ap-northeast-1
# S3_BUCKET=your-reports-bucket
```

### 9.3 package.json 脚本

```json
{
  "name": "report-service",
  "version": "1.0.0",
  "scripts": {
    "start":   "node src/server.js",
    "dev":     "nodemon src/server.js",
    "pm2":     "pm2 start ecosystem.config.js",
    "pm2:stop": "pm2 stop report-service"
  },
  "dependencies": {
    "better-sqlite3": "^9.4.0",
    "dotenv":         "^16.4.0",
    "express":        "^4.18.0",
    "highlight.js":   "^11.9.0",
    "marked":         "^12.0.0",
    "nanoid":         "^3.3.7"
  },
  "devDependencies": {
    "nodemon": "^3.1.0"
  }
}
```

> **注意**：nanoid v3 使用 CommonJS，v4+ 为 ESM。若项目未配置 ESM，推荐使用 `nanoid@3`。

### 9.4 开发环境启动

```bash
# 1. 安装依赖
npm install

# 2. 复制并配置环境变量
cp .env.example .env

# 3. 启动开发服务（热重载）
npm run dev

# 验证服务是否正常
curl http://localhost:3000/api/health
```

### 9.5 生产环境启动（PM2）

```javascript
// ecosystem.config.js

module.exports = {
  apps: [{
    name:         'report-service',
    script:       'src/server.js',
    instances:    2,                  // 多实例（注意：SQLite 单实例模式下设为 1）
    exec_mode:    'cluster',
    env_production: {
      NODE_ENV:  'production',
      PORT:       3000,
    },
    error_file:   './logs/err.log',
    out_file:     './logs/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss',
    max_memory_restart: '512M',
  }]
};
```

```bash
# 生产启动命令
npm install --production
pm2 start ecosystem.config.js --env production
pm2 save        # 保存进程列表（服务器重启后自动恢复）
pm2 startup     # 设置开机自启
```

---

## 10. 安全设计

### 10.1 API Key 鉴权（内部服务调用）

```javascript
// src/middlewares/auth.js

const config = require('../config');

function authMiddleware(req, res, next) {
  // 未配置 API Key 时跳过（开发模式）
  if (!config.apiKey) return next();

  const key = req.headers['x-api-key'];
  if (!key || key !== config.apiKey) {
    return res.status(401).json({
      success: false,
      error: { code: 'UNAUTHORIZED', message: '无效的 API Key' }
    });
  }
  next();
}

module.exports = { authMiddleware };
```

### 10.2 ID 安全性

使用 nanoid 生成 21 位随机字符（约 2^126 可能性），在 URL 中以 `rpt_` 前缀标识，避免遍历攻击：

```javascript
// src/utils/idGenerator.js
const { nanoid } = require('nanoid');

const generateReportId = () => `rpt_${nanoid(12)}`;

module.exports = { generateReportId };
```

### 10.3 过期校验

```javascript
// reportService.js 中的过期判断
function isExpired(expiresAt) {
  return new Date(expiresAt) < new Date();
}

// 访问时校验
if (!report) {
  const err = new Error('报告不存在');
  err.statusCode = 404;
  throw err;
}
if (isExpired(report.expires_at)) {
  const err = new Error('报告已过期');
  err.statusCode = 410;
  throw err;
}
```

---

## 11. 错误处理规范

```javascript
// src/middlewares/errorHandler.js

function errorHandler(err, req, res, next) {
  const statusCode = err.statusCode || 500;

  // 生产环境隐藏内部错误细节
  const message = statusCode === 500 && process.env.NODE_ENV === 'production'
    ? '服务器内部错误'
    : err.message;

  console.error(`[${new Date().toISOString()}] ${req.method} ${req.path}`, err);

  res.status(statusCode).json({
    success: false,
    error: {
      code:    err.code    || 'INTERNAL_ERROR',
      message: message,
    }
  });
}

module.exports = errorHandler;
```

**统一错误码**

| HTTP 状态码 | code | 场景 |
|------------|------|------|
| 400 | `VALIDATION_ERROR` | 请求参数缺失或格式错误 |
| 401 | `UNAUTHORIZED` | API Key 无效 |
| 404 | `NOT_FOUND` | 报告 ID 不存在 |
| 410 | `REPORT_EXPIRED` | 报告已过期 |
| 500 | `INTERNAL_ERROR` | 服务器内部错误 |

---

## 12. 部署方案

### 12.1 最小化单机部署

```
[故障诊断系统]
      │  POST /api/reports
      ▼
[Node.js report-service :3000]
      │
      ├── SQLite（元数据）
      └── 本地文件系统（MD + HTML）

用户通过浏览器访问链接（可配置 Nginx 反向代理）
```

### 12.2 Nginx 反向代理配置

```nginx
server {
    listen 80;
    server_name reports.your-domain.com;

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;

        # 报告 HTML 缓存 1 小时
        proxy_cache_valid  200 1h;
    }
}
```

### 12.3 快速集成示例

故障诊断系统调用报告服务的示例代码：

```javascript
// 在故障诊断系统中调用
const axios = require('axios');

async function publishDiagnosticReport(diagResult) {
  const markdownContent = generateMarkdown(diagResult); // 将诊断结果转为 MD

  const response = await axios.post('http://report-service:3000/api/reports', {
    title: `${diagResult.service} 故障报告 - ${new Date().toLocaleDateString()}`,
    content: markdownContent,
    expiresInDays: 30,
    metadata: {
      severity:   diagResult.severity,
      service:    diagResult.service,
      incidentId: diagResult.incidentId,
    }
  }, {
    headers: { 'X-API-Key': process.env.REPORT_SERVICE_KEY }
  });

  return response.data.data.url; // 返回报告链接给用户
}
```

---

*文档版本：v1.0 | 最后更新：2024-03-28*