import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import knexFactory, { type Knex } from "knex";
import { config, DATABASE_DIR } from "../config.js";

const require = createRequire(import.meta.url);
// 复用 CLI 同一份配置，确保「服务运行时」与「knex migrate」建表逻辑一致
const knexConfig = require("../../knexfile.cjs") as Knex.Config;

let _db: Knex | null = null;

export function getDb(): Knex {
  if (_db) return _db;
  if (config.db.client === "sqlite") {
    // 确保 SQLite 数据目录存在（BC-011）
    fs.mkdirSync(DATABASE_DIR, { recursive: true });
    const filename = config.db.sqlite.path;
    fs.mkdirSync(path.dirname(filename), { recursive: true });
  }
  _db = knexFactory(knexConfig);
  return _db;
}

/** 幂等建表：start.sh / 容器 entrypoint / 服务启动共用同一套迁移（FR-016）。 */
export async function migrateToLatest(): Promise<void> {
  const db = getDb();
  await db.migrate.latest();
}

export async function closeDb(): Promise<void> {
  if (_db) {
    await _db.destroy();
    _db = null;
  }
}
