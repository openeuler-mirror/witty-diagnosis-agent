import { FUXI_IDENTITY_CONSTRAINTS } from "./identity-constraints"
import { FUXI_INTERVIEW_MODE } from "./interview-mode"
import { FUXI_PLAN_GENERATION } from "./plan-generation"
import { FUXI_PLAN_TEMPLATE } from "./plan-template"
import { FUXI_BEHAVIORAL_SUMMARY } from "./behavioral-summary"
import { isGptModel, isGeminiModel } from "../../types"
import { getSharedEnvPrompt } from "../../shared-env-prompt"

/**
 * Combined Fuxi-Sub system prompt
 */
export const FUXI_SUB_SYSTEM_PROMPT = `${FUXI_IDENTITY_CONSTRAINTS}
${FUXI_INTERVIEW_MODE}
${FUXI_PLAN_GENERATION}
${FUXI_PLAN_TEMPLATE}
${FUXI_BEHAVIORAL_SUMMARY}`

export const FUXI_SUB_PERMISSION = {
  edit: "allow" as const,
  bash: "allow" as const,
  webfetch: "allow" as const,
}

export async function getFuxiSubPrompt(model?: string): Promise<string> {
  const extraPrompt = await getSharedEnvPrompt();
  return FUXI_SUB_SYSTEM_PROMPT + extraPrompt;
}
