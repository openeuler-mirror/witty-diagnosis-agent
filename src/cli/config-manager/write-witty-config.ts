import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs"
import { parseJsonc } from "../../shared"
import type { ConfigMergeResult, InstallConfig } from "../types"
import { getConfigDir, getWittyConfigPath } from "./config-context"
import { deepMergeRecord } from "./deep-merge-record"
import { ensureConfigDirectoryExists } from "./ensure-config-directory-exists"
import { formatErrorWithSuggestion } from "./format-error-with-suggestion"
import { generateWittyConfig } from "./generate-witty-config"

function isEmptyOrWhitespace(content: string): boolean {
  return content.trim().length === 0
}

export function writeWittyConfig(installConfig: InstallConfig): ConfigMergeResult {
  try {
    ensureConfigDirectoryExists()
  } catch (err) {
    return {
      success: false,
      configPath: getConfigDir(),
      error: formatErrorWithSuggestion(err, "create config directory"),
    }
  }

  const wittyConfigPath = getWittyConfigPath()

  try {
    const newConfig = generateWittyConfig(installConfig)

    if (existsSync(wittyConfigPath)) {
      try {
        const stat = statSync(wittyConfigPath)
        const content = readFileSync(wittyConfigPath, "utf-8")

        if (stat.size === 0 || isEmptyOrWhitespace(content)) {
          writeFileSync(wittyConfigPath, JSON.stringify(newConfig, null, 2) + "\n")
          return { success: true, configPath: wittyConfigPath }
        }

        const existing = parseJsonc<Record<string, unknown>>(content)
        if (!existing || typeof existing !== "object" || Array.isArray(existing)) {
          writeFileSync(wittyConfigPath, JSON.stringify(newConfig, null, 2) + "\n")
          return { success: true, configPath: wittyConfigPath }
        }

        const merged = deepMergeRecord(existing, newConfig)
        writeFileSync(wittyConfigPath, JSON.stringify(merged, null, 2) + "\n")
      } catch (parseErr) {
        if (parseErr instanceof SyntaxError) {
          writeFileSync(wittyConfigPath, JSON.stringify(newConfig, null, 2) + "\n")
          return { success: true, configPath: wittyConfigPath }
        }
        throw parseErr
      }
    } else {
      writeFileSync(wittyConfigPath, JSON.stringify(newConfig, null, 2) + "\n")
    }

    return { success: true, configPath: wittyConfigPath }
  } catch (err) {
    return {
      success: false,
      configPath: wittyConfigPath,
      error: formatErrorWithSuggestion(err, "write witty-diagnosis-agent config"),
    }
  }
}
