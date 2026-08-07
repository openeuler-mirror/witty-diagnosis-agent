import crypto from "node:crypto";
import Fastify from "fastify";
import cookie from "@fastify/cookie";
import multipart from "@fastify/multipart";
import { config } from "./config.js";
import { migrateToLatest, closeDb } from "./db/knex.js";
import { registerAuthRoutes } from "./auth.js";
import { registerTaskRoutes } from "./routes/tasks.js";
import { registerUploadRoutes } from "./routes/uploads.js";
import { registerQaRoutes } from "./routes/qa.js";
import * as repo from "./repositories.js";

/**
 * 后端服务入口（Fastify 单实例，D-005）。
 * 启动：建表（幂等 migrate）→ 崩溃恢复兜底 → 注册路由 → 留存清理定时任务。
 */

async function main() {
  // 表初始化：与 start.sh / 容器 entrypoint 复用同一套 Knex migrations（FR-016）
  await migrateToLatest();
  // 崩溃恢复：运行中任务在重启后无对应进程 → 置 failed 兜底（NFR-006）
  await repo.failOrphanRunning();
  // QA 模块崩溃恢复：残留 generating 的 assistant 消息置 failed（NFR-002，仅启用时）
  if (config.conversation.enabled) await repo.failOrphanQaGenerating();

  const app = Fastify({ logger: { level: process.env.LOG_LEVEL || "info" }, bodyLimit: 5 * 1024 * 1024 });

  await app.register(cookie, {
    secret: process.env.COOKIE_SECRET || crypto.randomBytes(32).toString("hex"),
  });
  await app.register(multipart, { limits: { fileSize: Number(process.env.UPLOAD_MAX_FILE_BYTES) || Infinity } });

  app.get("/api/health", async () => ({ ok: true, db: config.db.client }));
  // 能力探测：前端据此显隐 QA 导航（DQ-003 / FR-011）
  app.get("/api/capabilities", async () => ({ qa: config.conversation.enabled }));

  registerAuthRoutes(app);
  registerTaskRoutes(app);
  registerUploadRoutes(app);
  // QA 可选模块：仅在启用时注册路由（未装则路由不可用，BC-001）
  if (config.conversation.enabled) {
    registerQaRoutes(app);
    app.log.info("QA module enabled (已知问题对话查询)");
  }

  // 留存清理（N 天，BC-007 / FR-015）：每小时扫描一次
  const cleanup = setInterval(
    () => {
      repo.cleanupExpired().catch((e) => app.log.error(e, "cleanup failed"));
    },
    60 * 60 * 1000,
  );

  const shutdown = async () => {
    clearInterval(cleanup);
    await app.close();
    await closeDb();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  await app.listen({ port: config.http.port, host: config.http.host });
  app.log.info(`witty-diagnosis-web server listening on ${config.http.host}:${config.http.port} (db=${config.db.client})`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
