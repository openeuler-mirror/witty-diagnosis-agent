/**
 * 故障运维诊断（Xuanyuan）模块 · 驱动工厂（web/server 端消费入口）。
 *
 * 仅静态 import **零外部依赖** 的 mock 驱动与类型；真实 opencode 驱动经**运行时动态 import**
 * 加载（specifier 为变量，tsc 不跟随），从而保证 web/server 的 `tsc --noEmit` 编译路径
 * 不被 @opencode-ai/sdk 污染（与 taiyi/README.md 的模块边界约定一致）。opencode-driver.ts 的
 * 类型检查由根工程覆盖（根工程含 @opencode-ai/sdk）。
 */

import { createMockDriver, type MockDriverConfig } from "./mock-driver.js";
import type { TaskDriver } from "./types.js";

export type { TaskDriver, TaskDriverInput, TaskDriverEvent, TaskOnlineTarget, Stage } from "./types.js";
export { STAGE_ORDER, STAGE_PROGRESS } from "./types.js";

export interface TaskDriverConfig {
  /** 驱动选择：mock（默认）| opencode（真实路径，需配置模型/opencode 可用）。 */
  driver: "mock" | "opencode";
  mock?: MockDriverConfig;
  opencode?: {
    model?: string;
    outputLanguage?: "zh" | "en";
    serverTimeoutMs?: number;
    opencodeBin?: string;
  };
}

export async function createTaskDriver(cfg: TaskDriverConfig): Promise<TaskDriver> {
  if (cfg.driver === "opencode") {
    // specifier 显式拓宽为 string（非字面量），tsc 不跟随解析，避免把 @opencode-ai/sdk
    // 带进 web/server 的 tsc --noEmit 编译路径（其类型检查由根工程覆盖）。
    const spec = "./opencode-driver.js" as string;
    const mod = (await import(spec)) as {
      createOpencodeDriver: (c?: {
        model?: string;
        outputLanguage?: "zh" | "en";
        serverTimeoutMs?: number;
        opencodeBin?: string;
      }) => TaskDriver;
    };
    return mod.createOpencodeDriver(cfg.opencode);
  }
  return createMockDriver(cfg.mock);
}
