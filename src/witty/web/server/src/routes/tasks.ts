import { execFileSync, execSync } from "node:child_process";
import crypto from "node:crypto";
import path from "node:path";
import os from "node:os";
import net from "node:net";
import dns from "node:dns/promises";
import fs from "node:fs";
import { config } from "../config.js";
import type { FastifyInstance } from "fastify";
import { requireUser } from "../auth.js";
import * as repo from "../repositories.js";
import * as scheduler from "../scheduler.js";
import * as vault from "../vault.js";
import { subscribe } from "../streamHub.js";
import type { CreateTaskInput, StreamEvent, TaskStatus } from "../types.js";


/** 校验 host 格式：仅允许合法 IPv4 / IPv6 / RFC 1123 主机名，防范命令注入。 */
function isValidHost(host: string): boolean {
  if (!host || host.length > 255) return false;
  // 使用 net.isIP 判断 IP（覆盖 IPv4 和全部 IPv6 简写格式）
  if (net.isIP(host) !== 0) return true;
  // RFC 1123 主机名（含单标签如 localhost）
  return /^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$|^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(host);
}

/** 转义 ansible INI 值中的特殊字符：双引号包裹，内部转义反斜杠和双引号。
 * 防止密码/用户名含 # = ; 空格 等 INI 元字符导致解析截断或污染。 */
function escapeIniValue(s: string): string {
  return '"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
}
/**
 * Task API（对应 02 §6.1 IF-N02~N04）。
 * 所有读写强制 owner == 当前用户；越权统一 404（NFR-003 / 不泄露存在性）。
 */

export function registerTaskRoutes(app: FastifyInstance): void {
  // ---- 测连通性（任务创建前，无任务态，仅需登录）IF-N02b / BC-003 ----
  app.post("/api/tasks/connectivity-test", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const b = (req.body ?? {}) as { hostIp?: string; sshUser?: string; sshPassword?: string; sshPort?: number };
    if (!b.hostIp || !b.sshUser || !b.sshPassword) {
      reply.code(400);
      return { ok: false, reason: "缺少主机 IP / 账号 / 密码" };
    }
    const host = b.hostIp;
    const port = String(b.sshPort || 22);
    const sshUser = b.sshUser;

    // 安全校验：必须放在 mock 判断之前，确保始终生效（防范命令注入）
    if (!isValidHost(host)) {
      reply.code(400);
      return { ok: false, reason: "主机地址格式不合法: " + host };
    }

    // TASK_DRIVER=mock ? 模拟探测（联调用）: 真实 SSH 探测
    if (config.task.driver === "mock") {
      await new Promise((r) => setTimeout(r, 600));
      return { ok: true };
    }

    // 第一步：快速检查 TCP 端口是否开放（3s 内判定）
    let portOpen = false;
    // 使用 execFileSync 替代字符串拼接，避免命令注入
    try {
      execFileSync("timeout", ["3", "nc", "-zv", "-w", "2", host, port], { timeout: 5000 });
      portOpen = true;
    } catch {
      try {
        execFileSync("bash", ["-c", "echo >/dev/tcp/\"$1\"/\"$2\"", "bash", host, port], { timeout: 4000 });
        portOpen = true;
      } catch {
        portOpen = false;
      }
    }
    if (!portOpen) {
      // DNS 解析（用 Node.js dns 模块替代 shell 命令，彻底消除注入风险）
      try {
        await dns.resolve(host);
        return { ok: false, reason: "目标主机 " + host + " SSH 端口(" + port + ")未开放或无响应" };
      } catch {
        return { ok: false, reason: "无法解析主机名 " + host + "，请检查地址" };
      }
    }

    // 第二步：端口已通，检测 sshpass 并验证凭据
    try {
      execSync("which sshpass", { encoding: "utf8" });
    } catch {
      return { ok: false, reason: "主机可达(端口已开放)，但缺少 sshpass 无法验证密码。请安装: sudo apt-get install sshpass" };
    }

    const tmpFile = path.join(os.tmpdir(), "conn-" + crypto.randomUUID() + ".ini");
    let controlPath = "";
    // ansible 对 127.0.0.1 会切 local 绕过 SSH，改用 127.0.0.2
    const invHost = host === "127.0.0.1" ? "127.0.0.2" : host;
    const invContent = "[test]\n" + invHost + " ansible_user=" + escapeIniValue(sshUser) + " ansible_port=" + escapeIniValue(port) + " ansible_password=" + escapeIniValue(b.sshPassword) + " ansible_connection=ssh";
    try {
      fs.writeFileSync(tmpFile, invContent, { mode: 0o600 });
      controlPath = "/tmp/ansible-conn-" + crypto.randomUUID() + ".sock";
      const out = execSync(
        "ansible -i \"" + tmpFile + "\" test -m ping -o --ssh-common-args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ControlMaster=no -o ControlPath=" + controlPath + "'",
        { timeout: 8000, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] });
      if (out.includes("SUCCESS")) {
        return { ok: true };
      }
      return { ok: false, reason: "SSH 连接失败，请检查凭据" };
    } catch (err) {
      const stderr = (err && typeof err === "object" && "stderr" in err) ? (err as {stderr:string}).stderr : "";
      const stdout = (err && typeof err === "object" && "stdout" in err) ? (err as {stdout:string}).stdout : "";
      const msg = [stderr, stdout, err instanceof Error ? err.message : ""].filter(Boolean).join(" | ");
      let reason = msg.includes("Permission denied") || msg.includes("Authentication failure") || msg.includes("authentication") ? "认证失败，请检查账号和密码"
        : msg.includes("UNREACHABLE") ? "目标主机不可达"
        : msg.includes("sshpass") ? "需要安装 sshpass 才能验证密码"
        : "";
      if (!reason) {
        reason = "连接失败: " + msg.slice(0, 200).replace(/\n/g, " ");
      }
      return { ok: false, reason };
    } finally {
      try { fs.unlinkSync(tmpFile); } catch { /* ignore */ }
      try { fs.unlinkSync(controlPath); } catch { /* ignore */ }
    }
  });
  // ---- 创建任务 IF-N02 ----
  app.post("/api/tasks", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const input = (req.body ?? {}) as CreateTaskInput;

    // 必填校验（BC-008 / DC-001~003）
    if (!input.title?.trim() || !input.faultTime?.trim() || (input.mode !== "online" && input.mode !== "offline")) {
      reply.code(400);
      return { error: "故障现象、故障时间、运维类型为必填" };
    }

    if (input.mode === "online") {
      if (!input.hostIp || !input.sshUser || !input.sshPassword) {
        reply.code(400);
        return { error: "在线诊断需填写主机 IP / 账号 / 密码" };
      }
      // 连通性门禁（BC-003）
      if (!input.connectivityVerified) {
        reply.code(400);
        return { error: "请先测试连通性，通过后方可执行诊断" };
      }
    } else {
      const hasUploads = !!input.uploadIds && input.uploadIds.length > 0;
      const logPath = input.logPath?.trim();
      if (!hasUploads && !logPath) {
        reply.code(400);
        return { error: "离线分析需上传日志文件，或指定服务器日志路径" };
      }
      // 服务器路径来源：校验后端可访问（DC-008 / 防止指向不存在路径）
      if (logPath && !hasUploads && !fs.existsSync(logPath)) {
        reply.code(400);
        return { error: `服务器路径不存在或后端无法访问：${logPath}` };
      }
    }

    const taskId = await repo.createTask({
      ownerId: user.id,
      title: input.title.trim(),
      faultTime: input.faultTime.trim(),
      mode: input.mode,
      target:
        input.mode === "online"
          ? { hostIp: input.hostIp!, sshUser: input.sshUser!, sshPort: input.sshPort ?? 22 }
          : undefined,
    });

    if (input.mode === "online") {
      // 凭据进内存保险箱（不落库，BC-004）
      vault.stage(taskId, {
        hostIp: input.hostIp!,
        sshUser: input.sshUser!,
        sshPort: input.sshPort ?? 22,
        sshPassword: input.sshPassword!,
      });
    } else {
      if (input.uploadIds && input.uploadIds.length > 0) await repo.attachUploadsToTask(taskId, input.uploadIds);
      if (input.logPath?.trim()) await repo.addServerPathSource(taskId, input.logPath.trim());
    }

    scheduler.enqueue(taskId);
    reply.code(201);
    return { taskId, status: "queued" as TaskStatus };
  });

  // ---- 任务列表 IF-N04a ----
  app.get("/api/tasks", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const type = ((req.query as { type?: string }).type as "all" | "online" | "offline") || "all";
    return repo.listTasks(user.id, ["all", "online", "offline"].includes(type) ? type : "all");
  });

  // ---- 任务详情 IF-N04b ----
  app.get("/api/tasks/:id", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const id = (req.params as { id: string }).id;
    const task = await repo.getTaskForOwner(id, user.id);
    if (!task) {
      reply.code(404);
      return { error: "not found" };
    }
    const logs = await repo.listLogs(id);
    return { ...task, logs };
  });

  // ---- 实时进度 / 日志（SSE）IF-N03 ----
  app.get("/api/tasks/:id/stream", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const id = (req.params as { id: string }).id;
    const task = await repo.getTaskForOwner(id, user.id);
    if (!task) {
      reply.code(404);
      return { error: "not found" };
    }

    // 接管响应：Fastify 不再管理这条长连接（SSE）
    reply.hijack();
    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });

    const send = (event: StreamEvent) => {
      reply.raw.write(`data: ${JSON.stringify(event)}\n\n`);
    };

    // 首帧快照（断连可重连续传：前端基于快照对齐）
    const logs = await repo.listLogs(id);
    send({ type: "snapshot", status: task.status, progress: task.progress, stage: task.currentStage, logs });

    const unsubscribe = subscribe(id, send);
    const heartbeat = setInterval(() => reply.raw.write(": ping\n\n"), 15000);

    req.raw.on("close", () => {
      clearInterval(heartbeat);
      unsubscribe();
    });
    // 已 hijack，连接保持打开，无需返回
  });

  // ---- 取消 / 重试 IF-N04c ----
  app.post("/api/tasks/:id/cancel", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const id = (req.params as { id: string }).id;
    const task = await repo.getTaskForOwner(id, user.id);
    if (!task) {
      reply.code(404);
      return { error: "not found" };
    }
    await scheduler.cancel(id);
    return { status: "canceled" as TaskStatus };
  });

  app.post("/api/tasks/:id/retry", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const id = (req.params as { id: string }).id;
    const task = await repo.getTaskForOwner(id, user.id);
    if (!task) {
      reply.code(404);
      return { error: "not found" };
    }
    if (task.status === "running" || task.status === "queued") {
      reply.code(409);
      return { error: "任务进行中，无需重试" };
    }
    await scheduler.retry(id);
    return { status: "queued" as TaskStatus };
  });

  // ---- 删除 IF-N04c（运行中不可删，需先取消，BC-007）----
  app.delete("/api/tasks/:id", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const id = (req.params as { id: string }).id;
    const task = await repo.getTaskForOwner(id, user.id);
    if (!task) {
      reply.code(404);
      return { error: "not found" };
    }
    if (task.status === "running") {
      reply.code(409);
      return { error: "运行中任务需先取消方可删除" };
    }
    await repo.deleteTask(id);
    return { ok: true };
  });

  // ---- 报告查看 / 下载 IF-N04d ----
  app.get("/api/tasks/:id/report", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const id = (req.params as { id: string }).id;
    const task = await repo.getTaskForOwner(id, user.id);
    if (!task) {
      reply.code(404);
      return { error: "not found" };
    }
    const report = await repo.getReport(id);
    if (!report) {
      reply.code(404);
      return { error: "report not ready" };
    }
    const { fixable, fixPlan } = extractFixInfo(report);
    return {
      ...report,
      fixable,
      fixPlan,
      reportUrl: `${req.protocol}://${req.hostname}/api/tasks/${id}/report`,
    };
  });

  // ---- 评分 IF-N04e ----
  app.put("/api/tasks/:id/rating", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const id = (req.params as { id: string }).id;
    const task = await repo.getTaskForOwner(id, user.id);
    if (!task) {
      reply.code(404);
      return { error: "not found" };
    }
    const b = (req.body ?? {}) as { stars?: number; note?: string };
    const stars = Number(b.stars);
    if (!Number.isInteger(stars) || stars < 1 || stars > 5) {
      reply.code(400);
      return { error: "评分需为 1-5 的整数" };
    }
    await repo.upsertRating(id, stars, b.note);
    return { stars };
  });
}

/**
 * 从报告中抽取「能否修复 / 修复方案」。
 *  - HTML 报告（Baize 产出）：切出「修复方案」章节，剥掉所有 HTML 标签，返回纯文本字符串
 *    （保留标题、子节 4.1/4.2、表格的每行内容，行间以换行分隔）。
 *  - 结构化报告（mock/历史）：把命中章节的 blocks 拼成纯文本。
 *  - fixable：命中且抽到非空文本 → "能修复"；否则 "不能修复"。
 */
function extractFixInfo(report: import("../types.js").ReportPayload): { fixable: "能修复" | "不能修复"; fixPlan: string } {
  const kind = (report as { kind?: string }).kind;
  const rawHtml = kind === "html"
    ? extractFixSectionHtml((report as { html: string }).html)
    : renderStructuredFixSection(report as import("../types.js").ReportDTO);
  const plan = htmlToPlainText(rawHtml);
  return { fixable: plan ? "能修复" : "不能修复", fixPlan: plan };
}

/**
 * 把「修复方案」章节的 HTML 片段转成可读纯文本：
 *  - 块级标签（h/p/li/tr/table/…）→ 换行分隔；
 *  - 表格的 <td>/<th> 之间 → 两个空格；
 *  - 剥掉所有标签，去多余空白，去空行。
 */
function htmlToPlainText(html: string): string {
  if (!html) return "";
  let s = html
    .replace(/<\s*br\s*\/?>/gi, "\n")
    .replace(/<\/(t[dh])>/gi, "  ")           // 表格单元格之间用双空格
    .replace(/<\/(tr|table|thead|tbody|li|p|h[1-6]|div|blockquote|section|article|hr|ul|ol)>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
  return s
    .split("\n")
    .map((line) => line.replace(/[ \t]+/g, " ").trim())
    .filter(Boolean)
    .join("\n");
}

function stripHtml(s: string): string {
  return s.replace(/<[^>]+>/g, "").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/\s+/g, " ").trim();
}

// Baize 报告实际使用的多套「修复」章节标题；越靠前优先级越高。
const FIX_HEADING_RE = /修复方案|修复计划|处置建议|修复建议|处置方案|行动建议/;
// 排除章节：这些标题里也可能带「修复」字样，但不是我们要的方案正文
const FIX_HEADING_EXCLUDE_RE = /自查|质量|说明|概览|时间线|排查过程|因果链|逻辑树/;

/**
 * 切出「修复方案」章节的原始 HTML（从命中的 <hN> 到下一个同级/更高级 <hN>，含标题本身）。
 * 用于前端 v-html / innerHTML 直接渲染 —— 保留 Baize 的表格、层级、样式。
 */
function extractFixSectionHtml(html: string): string {
  if (!html) return "";
  const headings: { level: number; text: string; start: number; end: number }[] = [];
  const headingRe = /<h([1-6])[^>]*>([\s\S]*?)<\/h\1>/gi;
  let hm: RegExpExecArray | null;
  while ((hm = headingRe.exec(html))) {
    headings.push({
      level: Number(hm[1]),
      text: stripHtml(hm[2] ?? ""),
      start: hm.index,
      end: headingRe.lastIndex,
    });
  }
  for (let i = 0; i < headings.length; i++) {
    const h = headings[i]!;
    if (!FIX_HEADING_RE.test(h.text) || FIX_HEADING_EXCLUDE_RE.test(h.text)) continue;
    let endIdx = html.length;
    for (let j = i + 1; j < headings.length; j++) {
      if (headings[j]!.level <= h.level) {
        endIdx = headings[j]!.start;
        break;
      }
    }
    // 从标题起点开始截，含标题本体；normalize 空白但保留结构
    return html.slice(h.start, endIdx).trim();
  }
  return "";
}

/** 结构化报告（mock/历史）里把「修复方案」相关 section 的 blocks 拼成 HTML。 */
function renderStructuredFixSection(report: import("../types.js").ReportDTO): string {
  for (const sec of report.sections ?? []) {
    if (!FIX_HEADING_RE.test(sec.label ?? "") || FIX_HEADING_EXCLUDE_RE.test(sec.label ?? "")) continue;
    const parts: string[] = [`<h2>${escapeHtml(sec.label)}</h2>`];
    for (const b of sec.blocks ?? []) {
      const rendered = renderBlockToHtml(b);
      if (rendered) parts.push(rendered);
    }
    if (parts.length > 1) return parts.join("\n");
  }
  return "";
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c] as string);
}

function renderBlockToHtml(b: import("../types.js").ReportBlock): string {
  switch (b.t) {
    case "p": return `<p>${b.html}</p>`;
    case "ol": return `<ol>${b.items.map((x) => `<li>${escapeHtml(x)}</li>`).join("")}</ol>`;
    case "ul": return `<ul>${b.items.map((x) => `<li>${escapeHtml(x)}</li>`).join("")}</ul>`;
    case "table": return `<table><thead><tr>${b.head.map((h) => `<th>${escapeHtml(h)}</th>`).join("")}</tr></thead><tbody>${b.rows.map((r) => `<tr>${r.map((c) => `<td>${escapeHtml(c)}</td>`).join("")}</tr>`).join("")}</tbody></table>`;
    case "code": return `<pre><code>${escapeHtml(b.text)}</code></pre>`;
    case "tone": return `<div class="tone ${b.tone}">${b.html}</div>`;
    default: return "";
  }
}

