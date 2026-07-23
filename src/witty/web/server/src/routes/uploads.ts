import fs from "node:fs";
import path from "node:path";
import { pipeline } from "node:stream/promises";
import { v4 as uuid } from "uuid";
import type { FastifyInstance } from "fastify";
import { requireUser } from "../auth.js";
import { config } from "../config.js";
import * as repo from "../repositories.js";

/**
 * 离线日志上传 IF-N02c（流式落盘，NFR-007 / DC-008）。
 * 仅允许 .log / .tar.gz / .zip；不设大小上限，但有总磁盘配额兜底。
 */

const ALLOWED = [".log", ".tar.gz", ".zip"];

function isAllowed(name: string): boolean {
  const lower = name.toLowerCase();
  return ALLOWED.some((ext) => lower.endsWith(ext));
}

function dirSize(dir: string): number {
  if (!fs.existsSync(dir)) return 0;
  let total = 0;
  for (const f of fs.readdirSync(dir)) {
    try {
      total += fs.statSync(path.join(dir, f)).size;
    } catch {
      /* ignore */
    }
  }
  return total;
}

export function registerUploadRoutes(app: FastifyInstance): void {
  app.post("/api/uploads", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;

    const part = await req.file();
    if (!part) {
      reply.code(400);
      return { error: "缺少上传文件" };
    }
    if (!isAllowed(part.filename)) {
      reply.code(415);
      return { error: "仅支持 .log / .tar.gz / .zip 格式" };
    }

    fs.mkdirSync(config.upload.dir, { recursive: true });
    if (config.upload.diskQuotaBytes > 0 && dirSize(config.upload.dir) >= config.upload.diskQuotaBytes) {
      reply.code(507);
      return { error: "上传磁盘配额已满，请清理后重试" };
    }

    const stored = path.join(config.upload.dir, `${uuid()}-${path.basename(part.filename)}`);
    await pipeline(part.file, fs.createWriteStream(stored));
    const size = fs.statSync(stored).size;

    const dto = await repo.createUpload(part.filename, stored, size);
    reply.code(201);
    return dto;
  });
}
