import os from "node:os";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

const MODULE_DIR = path.dirname(fileURLToPath(import.meta.url));

export function getEnvFileCandidates(cwd = process.cwd()): string[] {
  const candidates = [
    path.join(cwd, ".env"),
    path.resolve(MODULE_DIR, "..", ".env"),
  ];
  return [...new Set(candidates)];
}

// 加载 .env（Node 20.6+ 内置，零依赖）；优先 cwd，其次回退到 web/server 目录自身。
try {
  const loadEnvFile = (process as { loadEnvFile?: (f?: string) => void }).loadEnvFile;
  if (typeof loadEnvFile === "function") {
    for (const p of getEnvFileCandidates()) {
      if (!fs.existsSync(p)) continue;
      loadEnvFile(p);
    }
  }
} catch {
  /* ignore */
}

/**
 * 集中配置（对应 02 §6.3 配置接口）。
 * 全部经环境变量覆盖，给出与设计一致的工程默认值。
 */

function envInt(name: string, dflt: number): number {
  const v = process.env[name];
  if (!v) return dflt;
  const n = Number(v);
  return Number.isFinite(n) ? n : dflt;
}

function envBool(name: string, dflt: boolean): boolean {
  const v = process.env[name];
  if (v === undefined || v === "") return dflt;
  return v === "true" || v === "1" || v.toLowerCase() === "yes";
}

function envOneOf<const T extends readonly string[]>(name: string, allowed: T, dflt: T[number]): T[number] {
  const v = process.env[name];
  if (!v) return dflt;
  return (allowed as readonly string[]).includes(v) ? (v as T[number]) : dflt;
}

/** 默认数据根目录 ~/.witty-diagnosis-agent （与 agent 状态根目录同父，BC-011）。 */
export const AGENT_HOME = path.join(os.homedir(), ".witty-diagnosis-agent");
export const DATABASE_DIR = path.join(AGENT_HOME, "database");

export type DbClient = "sqlite" | "mysql";

export const config = {
  http: {
    port: envInt("PORT", 8787),
    host: process.env.HOST || "0.0.0.0",
  },
  db: {
    client: (process.env.DB_CLIENT as DbClient) || "sqlite",
    sqlite: {
      path: process.env.DB_SQLITE_PATH || path.join(DATABASE_DIR, "witty.db"),
    },
    mysql: {
      host: process.env.DB_MYSQL_HOST || "127.0.0.1",
      port: envInt("DB_MYSQL_PORT", 3306),
      user: process.env.DB_MYSQL_USER || "witty",
      password: process.env.DB_MYSQL_PASSWORD || "",
      database: process.env.DB_MYSQL_DATABASE || "witty",
    },
  },
  scheduler: {
    maxConcurrent: envInt("SCHEDULER_MAX_CONCURRENT", 4),
  },
  task: {
    retentionDays: envInt("TASK_RETENTION_DAYS", 30),
    timeoutMs: envInt("RUNNER_TASK_TIMEOUT_MS", 1800000),
    /**
     * 诊断驱动选择（对应 02 §D-001/§D-002）：
     *  - mock（默认）：确定性阶段时序模拟，无需模型/opencode，便于联调。
     *  - opencode：真实路径，每任务 createOpencode + 重定向 HOME/XDG 隔离，驱动 xuanyuan 全链路。
     */
    driver: envOneOf("TASK_DRIVER", ["mock", "opencode"] as const, "mock"),
    /** 真实路径每任务专属 HOME 根目录（隔离根，BC-011/D-001）。 */
    ocHomeBase: process.env.TASK_OPENCODE_HOME_BASE || path.join(AGENT_HOME, "task-homes"),
    /**
     * opencode 二进制路径（真实路径）。留空=按 PATH/which 自动解析（复刻 cli/run 的
     * withWorkingOpencodePath）；显式指定可避免 PATH 未含该目录时找不到 server 二进制。
     */
    opencodeBin: process.env.TASK_OPENCODE_BIN || undefined,
    /** 绑定到 xuanyuan 的模型（缺省走 opencode 平台默认/已配置凭据）。 */
    model: process.env.TASK_MODEL || undefined,
    /** 报告/叙述输出语言。 */
    outputLanguage: envOneOf("TASK_OUTPUT_LANGUAGE", ["zh", "en"] as const, "zh"),
    /** opencode server 启动超时（ms）。 */
    serverTimeoutMs: envInt("TASK_OPENCODE_SERVER_TIMEOUT_MS", 60000),
  },
  upload: {
    dir: process.env.UPLOAD_DIR || path.join(AGENT_HOME, "web-uploads"),
    diskQuotaBytes: envInt("UPLOAD_DISK_QUOTA_BYTES", 53687091200),
  },
  auth: {
    provider: process.env.AUTH_PROVIDER || "dev",
  },
  /**
   * 已知问题对话查询（QA）可选模块（对应 02 §6.3）。
   * enabled=false 时：路由不注册、capabilities.qa=false、前端隐藏入口（BC-001）。
   */
  conversation: {
    enabled: envBool("CONVERSATION_ENABLED", false),
    maxConcurrent: envInt("CONVERSATION_MAX_CONCURRENT", 10), // TBD-002
    timeoutMs: envInt("CONVERSATION_TIMEOUT_MS", 120000),
    questionMaxChars: envInt("CONVERSATION_QUESTION_MAX_CHARS", 4000), // DC-003/TBD-003
    ocHome: process.env.QA_OPENCODE_HOME || path.join(AGENT_HOME, "qa-home"),
  },
  /**
   * LightRAG 知识检索（QA 模块外部依赖）。
   * mock=true（默认且当未配置 endpoint 时）走内置 mock 知识，便于未灌库/未起容器时联调（G2）。
   * 端点/凭据经 env 注入，不入库明文、不进日志（NFR-004）。
   */
  lightrag: {
    mock: envBool("LIGHTRAG_MOCK", !process.env.LIGHTRAG_ENDPOINT),
    endpoint: process.env.LIGHTRAG_ENDPOINT || "http://localhost:9621",
    apiKey: process.env.LIGHTRAG_API_KEY || "lightrag1234",
    apiKeyHeader: process.env.LIGHTRAG_API_KEY_HEADER || "X-API-Key",
    timeoutMs: envInt("LIGHTRAG_TIMEOUT_MS", 120000),
    queryMode: envOneOf("LIGHTRAG_QUERY_MODE", ["local", "global", "hybrid", "naive", "mix", "bypass"] as const, "mix"),
    responseType: process.env.LIGHTRAG_RESPONSE_TYPE || "Multiple Paragraphs",
    includeChunkContent: envBool("LIGHTRAG_INCLUDE_CHUNK_CONTENT", true),
  },
} as const;

export type AppConfig = typeof config;
