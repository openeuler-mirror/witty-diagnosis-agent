/**
 * 已知问题问答（QA）模块 · 驱动工厂。
 *
 * 静态 import 零外部依赖的 mock 驱动；真实 opencode 驱动经运行时动态 import
 * 加载（specifier 为变量，tsc 不跟随），避免 web/server 编译路径被 @opencode-ai/sdk 污染。
 */

import { createMockDriver } from "./mock-driver.js";
import type { LightragClientConfig } from "../lightrag/client.js";
import type { QaDriver } from "./types.js";

export interface QaDriverConfig {
  /** 驱动选择：mock（默认）| opencode（真实路径，需模型配置）。 */
  driver: "mock" | "opencode";
  lightrag: LightragClientConfig;
  retrievalDelayMs?: number;
  tokenIntervalMs?: number;
  opencode?: {
    model?: string;
    serverTimeoutMs?: number;
  };
}

export async function createQaDriver(cfg: QaDriverConfig): Promise<QaDriver> {
  if (cfg.driver === "opencode") {
    try {
      const mod = await import("./opencode-driver.js");
      return mod.createOpencodeDriver(cfg.opencode ?? {});
    } catch (err) {
      throw new Error(
        "opencode 驱动加载失败，请确认 agents/taiyi/driver/opencode-driver.ts 存在。" +
        "若不需要 opencode 模式，设置 QA_DRIVER=mock"
      );
    }
  }
  return createMockDriver({
    lightrag: cfg.lightrag,
    retrievalDelayMs: cfg.retrievalDelayMs,
    tokenIntervalMs: cfg.tokenIntervalMs,
  });
}
