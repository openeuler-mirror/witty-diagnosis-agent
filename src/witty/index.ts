import type { Plugin } from "@opencode-ai/plugin"

import { createWittyHooks } from "./plugin"
import { log } from "./shared/log"

/**
 * witty-diagnosis-agent 插件入口（tsup 的 index 入口指向本文件）。
 */
export const WittyDiagnosisPlugin: Plugin = async (input) => {
  log("plugin: 加载", { directory: input.directory })
  return createWittyHooks(input)
}

export default WittyDiagnosisPlugin
