/**
 * 已知问题问答（QA）模块 · 驱动工厂。
 *
 * 本期：始终返回 mock 驱动（LightRAG 走 mock 或 real REST 均由 client 决定）。
 * real 路径（opencode 常驻 server）见 ../README.md 与 ./opencode-driver.ts 脚手架，
 * 待 @opencode-ai/sdk 接入后在此切换；切换对 web/server 透明（同一 QaDriver 契约）。
 */

import { createMockDriver } from "./mock-driver.js";
import type { LightragClientConfig } from "../lightrag/client.js";
import type { QaDriver } from "./types.js";

export interface QaDriverConfig {
  lightrag: LightragClientConfig;
  retrievalDelayMs?: number;
  tokenIntervalMs?: number;
}

export function createQaDriver(cfg: QaDriverConfig): QaDriver {
  return createMockDriver({
    lightrag: cfg.lightrag,
    retrievalDelayMs: cfg.retrievalDelayMs,
    tokenIntervalMs: cfg.tokenIntervalMs,
  });
}
