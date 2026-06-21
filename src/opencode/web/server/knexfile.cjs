/**
 * Knex 配置（CommonJS，供 `knex` CLI 与服务运行时共用）。
 * 默认 SQLite、可切 MySQL（仅改配置，业务代码无改动）——对应 02 §1.2 D-004 / §5.3。
 * 迁移脚本用 .cjs，跨方言（SQLite/MySQL）通用。
 */
const os = require("node:os");
const path = require("node:path");
const fs = require("node:fs");

// 加载 .env（Node 20.6+ 内置，零依赖）；缺失则忽略，回落到默认值
try {
  if (typeof process.loadEnvFile === "function" && fs.existsSync(path.join(process.cwd(), ".env"))) {
    process.loadEnvFile();
  }
} catch {
  /* ignore */
}

const AGENT_HOME = path.join(os.homedir(), ".witty-diagnosis-agent");
const DATABASE_DIR = path.join(AGENT_HOME, "database");

const client = process.env.DB_CLIENT || "sqlite";

const migrations = {
  directory: path.join(__dirname, "src", "db", "migrations"),
  loadExtensions: [".cjs"],
  tableName: "knex_migrations",
};

let config;
if (client === "mysql") {
  config = {
    client: "mysql2",
    connection: {
      host: process.env.DB_MYSQL_HOST || "127.0.0.1",
      port: Number(process.env.DB_MYSQL_PORT || 3306),
      user: process.env.DB_MYSQL_USER || "witty",
      password: process.env.DB_MYSQL_PASSWORD || "",
      database: process.env.DB_MYSQL_DATABASE || "witty",
    },
    pool: { min: 1, max: 5 },
    migrations,
  };
} else {
  const filename = process.env.DB_SQLITE_PATH || path.join(DATABASE_DIR, "witty.db");
  // 确保 SQLite 数据目录存在（knex CLI 不会自建，否则 SQLITE_CANTOPEN）BC-011
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  config = {
    client: "sqlite3",
    connection: { filename },
    useNullAsDefault: true,
    pool: {
      // SQLite 外键约束默认关闭，逐连接开启
      afterCreate: (conn, done) => conn.run("PRAGMA foreign_keys = ON", done),
    },
    migrations,
  };
}

// knex CLI 读取 default；服务运行时也 import 同一份
module.exports = config;
module.exports.development = config;
module.exports.production = config;
