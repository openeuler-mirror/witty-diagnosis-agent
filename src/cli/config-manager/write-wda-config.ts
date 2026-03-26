import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs"
import { parseJsonc } from "../../shared"
import type { ConfigMergeResult, InstallConfig } from "../types"
import { getConfigDir, getWdaConfigPath } from "./config-context"
import { deepMergeRecord } from "./deep-merge-record"
import { ensureConfigDirectoryExists } from "./ensure-config-directory-exists"
import { formatErrorWithSuggestion } from "./format-error-with-suggestion"
import { generateWdaConfig } from "./generate-wda-config"

function isEmptyOrWhitespace(content: string): boolean {
  return content.trim().length === 0
}

export function writeWdaConfig(installConfig: InstallConfig): ConfigMergeResult {
  try {
    ensureConfigDirectoryExists()
  } catch (err) {
    return {
      success: false,
      configPath: getConfigDir(),
      error: formatErrorWithSuggestion(err, "create config directory"),
    }
  }

  const wdaConfigPath = getWdaConfigPath()

  try {
    const newConfig = generateWdaConfig(installConfig)

    if (existsSync(wdaConfigPath)) {
      try {
        const stat = statSync(wdaConfigPath)
        const content = readFileSync(wdaConfigPath, "utf-8")

        if (stat.size === 0 || isEmptyOrWhitespace(content)) {
          writeFileSync(wdaConfigPath, JSON.stringify(newConfig, null, 2) + "\n")
          return { success: true, configPath: wdaConfigPath }
        }

        const existing = parseJsonc<Record<string, unknown>>(content)
        if (!existing || typeof existing !== "object" || Array.isArray(existing)) {
          writeFileSync(wdaConfigPath, JSON.stringify(newConfig, null, 2) + "\n")
          return { success: true, configPath: wdaConfigPath }
        }

        const merged = deepMergeRecord(newConfig, existing)
        writeFileSync(wdaConfigPath, JSON.stringify(merged, null, 2) + "\n")
      } catch (parseErr) {
        if (parseErr instanceof SyntaxError) {
          writeFileSync(wdaConfigPath, JSON.stringify(newConfig, null, 2) + "\n")
          return { success: true, configPath: wdaConfigPath }
        }
        throw parseErr
      }
    } else {
      writeFileSync(wdaConfigPath, JSON.stringify(newConfig, null, 2) + "\n")
    }

    return { success: true, configPath: wdaConfigPath }
  } catch (err) {
    return {
      success: false,
      configPath: wdaConfigPath,
      error: formatErrorWithSuggestion(err, "write witty-diagnosis-agent config"),
    }
  }
}
