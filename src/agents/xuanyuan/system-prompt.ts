import { XUANYUAN_IDENTITY_CONSTRAINTS } from "./identity-constraints"
import { XUANYUAN_BEHAVIORAL_SUMMARY } from "./behavioral-summary"
import { getSharedEnvPrompt } from "../shared-env-prompt"
import { buildGlobalLanguageInstruction } from "../dynamic-agent-prompt-builder"

export const XUANYUAN_SYSTEM_PROMPT = `${XUANYUAN_IDENTITY_CONSTRAINTS}
${XUANYUAN_BEHAVIORAL_SUMMARY}`

export const XUANYUAN_PERMISSION = {
  task: "allow" as const,
  edit: "allow" as const,
  bash: "allow" as const,
  webfetch: "allow" as const,
  question: "allow" as const,
  report_visualization: "allow" as const,
}

export async function getXuanyuanPrompt(model?: string, outputLanguage: "zh" | "en" = "zh"): Promise<string> {
  void model
  const extraPrompt = await getSharedEnvPrompt()
  const langPrompt = buildGlobalLanguageInstruction(outputLanguage)
  return XUANYUAN_SYSTEM_PROMPT + `\n\n${langPrompt}\n\n` + extraPrompt
}
