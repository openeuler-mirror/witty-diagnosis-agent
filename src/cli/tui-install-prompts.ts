import type { DetectedConfig, InstallConfig } from "./types"
import { detectedToInitialValues } from "./install-validators"

/**
 * Non-interactive TUI config:
 *
 * For your local workflow we don't want any interactive "Do you have X subscription?"
 * questions. This helper now derives an InstallConfig purely from detected defaults,
 * without prompting the user. All providers default to "no" unless already present
 * in the existing config.
 */
export async function promptInstallConfig(detected: DetectedConfig): Promise<InstallConfig | null> {
  const initial = detectedToInitialValues(detected)

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
  }
}
