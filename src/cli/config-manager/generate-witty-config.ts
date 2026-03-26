import type { InstallConfig } from "../types"
import { generateModelConfig } from "../model-fallback"

<<<<<<<< HEAD:src/cli/config-manager/generate-witty-config.ts
export function generateWittyConfig(installConfig: InstallConfig): Record<string, unknown> {
========
export function generateWdaConfig(installConfig: InstallConfig): Record<string, unknown> {
>>>>>>>> origin/master:src/cli/config-manager/generate-wda-config.ts
  return generateModelConfig(installConfig)
}
