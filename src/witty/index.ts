import type { Plugin } from "@opencode-ai/plugin"

import { createWittyHooks } from "./plugin"
import { log } from "./shared/log"

/**
 * witty-diagnosis-agent 净室插件入口。
 *
 * 净室重写完成后，tsup.config.ts 的 index 入口指向本文件（替代 src/opencode/index.ts）。
 */
export const WittyDiagnosisPlugin: Plugin = async (input) => {
  log("plugin: 加载", { directory: input.directory })
  return createWittyHooks(input)
}

export default WittyDiagnosisPlugin
