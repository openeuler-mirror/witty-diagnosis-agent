import type { InstallConfig } from "../types"
import { generateModelConfig } from "../model-fallback"

export function generateWdaConfig(installConfig: InstallConfig): Record<string, unknown> {
  return generateModelConfig(installConfig)
}
