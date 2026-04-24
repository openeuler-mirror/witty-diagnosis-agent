import type { DetectedConfig, InstallConfig } from "./types"
import { detectedToInitialValues } from "./install-validators"
import { select, isCancel } from "@clack/prompts"
import pc from "picocolors"

/**
 * Interactive TUI config:
 * Prompts user for language preference since this is critical.
 * Other provider configs are derived automatically for now.
 */
export async function promptInstallConfig(detected: DetectedConfig): Promise<InstallConfig | null> {
  const initial = detectedToInitialValues(detected)

  const languageResult = await select({
    message: "Select output language for Witty Diagnosis Agent / 选择 Witty Diagnosis Agent 的输出语言\n  (This affects all agents' reasoning, response, and report / 影响所有 Agent 的思考、回复和生成的报告)",
    options: [
      { value: "zh", label: "简体中文 (zh)" },
      { value: "en", label: "English (en)" },
    ],
    initialValue: initial.outputLanguage ?? "zh",
  })

  if (isCancel(languageResult)) {
    return null
  }

  const outputLanguage = languageResult as "zh" | "en"

  const claude = initial.claude ?? "no"
  const openai = initial.openai ?? "no"
  const gemini = initial.gemini ?? "no"
  const copilot = initial.copilot ?? "no"
  const opencodeZen = initial.opencodeZen ?? "no"
  const zaiCodingPlan = initial.zaiCodingPlan ?? "no"
  const kimiForCoding = initial.kimiForCoding ?? "no"

  return {
    hasClaude: claude !== "no",
    isMax20: claude === "max20",
    hasOpenAI: openai === "yes",
    hasGemini: gemini === "yes",
    hasCopilot: copilot === "yes",
    hasOpencodeZen: opencodeZen === "yes",
    hasZaiCodingPlan: zaiCodingPlan === "yes",
    hasKimiForCoding: kimiForCoding === "yes",
    outputLanguage,
  }
}
