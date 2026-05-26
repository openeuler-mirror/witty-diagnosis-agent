import type { InstallConfig } from "../types"
import { generateModelConfig } from "../model-fallback"

export function generateWittyConfig(installConfig: InstallConfig): Record<string, unknown> {
  return generateModelConfig(installConfig)
}
