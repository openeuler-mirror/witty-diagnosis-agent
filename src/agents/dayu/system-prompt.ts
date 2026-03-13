import { DAYU_IDENTITY_CONSTRAINTS } from "./identity-constraints"
import { DAYU_INTERVIEW_MODE } from "./interview-mode"
import { DAYU_BEHAVIORAL_SUMMARY } from "./behavioral-summary"

/**
 * Combined Dayu system prompt (model-agnostic, default).
 * Assembled from modular sections for maintainability.
 * 
 * NOTE: Only includes diagnostic orchestration related modules.
 * Sisyphus work plan modules (plan-generation, plan-template, high-accuracy-mode)
 * are intentionally excluded to avoid interference with diagnostic workflow.
 */
export const DAYU_SYSTEM_PROMPT = `${DAYU_IDENTITY_CONSTRAINTS}
${DAYU_INTERVIEW_MODE}
${DAYU_BEHAVIORAL_SUMMARY}`

/**
 * Dayu planner permission configuration.
 * Allows write/edit for plan files (.md only, enforced by md-only hook).
 * Question permission allows agent to ask user questions via OpenCode's QuestionTool.
 */
export const DAYU_PERMISSION = {
  edit: "allow" as const,
  bash: "allow" as const,
  webfetch: "allow" as const,
  question: "allow" as const,
}

export type DayuPromptSource = "default" | "gpt" | "gemini"

/**
 * Determines which Dayu prompt to use based on model.
 *
 * NOTE: For now Dayu always uses the unified orchestration prompt.
 * GPT / Gemini specializations are intentionally ignored to keep
 * the diagnostic orchestration behavior consistent across models.
 */
export function getDayuPromptSource(model?: string): DayuPromptSource {
  return "default"
}

/**
 * Gets the appropriate Dayu prompt based on model.
 *
 * Currently returns the unified orchestration prompt for all models.
 */
export function getDayuPrompt(model?: string): string {
  // keep signature for future model-specific variants if needed
  void model
  return DAYU_SYSTEM_PROMPT
}
