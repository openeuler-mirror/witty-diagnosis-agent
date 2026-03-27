import { existsSync, readFileSync } from "node:fs"
import { parseJsonc } from "../../shared"
import type { DetectedConfig } from "../types"
import { getWittyConfigPath } from "./config-context"
import { detectConfigFormat } from "./opencode-config-format"
import { parseOpenCodeConfigFileWithError } from "./parse-opencode-config-file"

function detectProvidersFromWittyConfig(): {
  hasOpenAI: boolean
  hasOpencodeZen: boolean
  hasZaiCodingPlan: boolean
  hasKimiForCoding: boolean
} {
  const wittyConfigPath = getWittyConfigPath()
  if (!existsSync(wittyConfigPath)) {
    return { hasOpenAI: true, hasOpencodeZen: true, hasZaiCodingPlan: false, hasKimiForCoding: false }
  }

  try {
    const content = readFileSync(wittyConfigPath, "utf-8")
    const wittyConfig = parseJsonc<Record<string, unknown>>(content)
    if (!wittyConfig || typeof wittyConfig !== "object") {
      return { hasOpenAI: true, hasOpencodeZen: true, hasZaiCodingPlan: false, hasKimiForCoding: false }
    }

    const configStr = JSON.stringify(wittyConfig)
    const hasOpenAI = configStr.includes('"openai/')
    const hasOpencodeZen = configStr.includes('"opencode/')
    const hasZaiCodingPlan = configStr.includes('"zai-coding-plan/')
    const hasKimiForCoding = configStr.includes('"kimi-for-coding/')

    return { hasOpenAI, hasOpencodeZen, hasZaiCodingPlan, hasKimiForCoding }
  } catch {
    return { hasOpenAI: true, hasOpencodeZen: true, hasZaiCodingPlan: false, hasKimiForCoding: false }
  }
}

export function detectCurrentConfig(): DetectedConfig {
  const result: DetectedConfig = {
    isInstalled: false,
    hasClaude: true,
    isMax20: true,
    hasOpenAI: true,
    hasGemini: false,
    hasCopilot: false,
    hasOpencodeZen: true,
    hasZaiCodingPlan: false,
    hasKimiForCoding: false,
  }

  const { format, path } = detectConfigFormat()
  if (format === "none") {
    return result
  }

  const parseResult = parseOpenCodeConfigFileWithError(path)
  if (!parseResult.config) {
    return result
  }

  const openCodeConfig = parseResult.config
  const plugins = openCodeConfig.plugin ?? []
  result.isInstalled = plugins.some((p) => p.startsWith("witty-diagnosis-agent"))

  if (!result.isInstalled) {
    return result
  }

  result.hasGemini = plugins.some((p) => p.startsWith("opencode-antigravity-auth"))

  const { hasOpenAI, hasOpencodeZen, hasZaiCodingPlan, hasKimiForCoding } = detectProvidersFromWittyConfig()
  result.hasOpenAI = hasOpenAI
  result.hasOpencodeZen = hasOpencodeZen
  result.hasZaiCodingPlan = hasZaiCodingPlan
  result.hasKimiForCoding = hasKimiForCoding

  return result
}
