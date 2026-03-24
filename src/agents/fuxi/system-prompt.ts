import { FUXI_IDENTITY_CONSTRAINTS } from "./identity-constraints"
import { FUXI_INTERVIEW_MODE } from "./interview-mode"
import { FUXI_PLAN_GENERATION } from "./plan-generation"
import { FUXI_PLAN_TEMPLATE } from "./plan-template"
import { FUXI_BEHAVIORAL_SUMMARY } from "./behavioral-summary"
import { isGptModel, isGeminiModel } from "../types"

/**
 * Combined Fuxi system prompt (Claude-optimized, default).
 * Assembled from modular sections for maintainability.
 */
export const FUXI_SYSTEM_PROMPT = `${FUXI_IDENTITY_CONSTRAINTS}
${FUXI_INTERVIEW_MODE}
${FUXI_PLAN_GENERATION}
${FUXI_PLAN_TEMPLATE}
${FUXI_BEHAVIORAL_SUMMARY}`

/**
 * Fuxi planner permission configuration.
 * Allows write/edit for plan files (.md only, enforced by fuxi-md-only hook).
 * Question permission allows agent to ask user questions via OpenCode's QuestionTool.
 */
export const FUXI_PERMISSION = {
  edit: "allow" as const,
  bash: "allow" as const,
  webfetch: "allow" as const,
  question: "allow" as const,
}

export type FuxiPromptSource = "default" | "gpt" | "gemini"

/**
 * Determines which Fuxi prompt to use based on model.
 */
export function getFuxiPromptSource(model?: string): FuxiPromptSource {
  if (model && isGptModel(model)) {
    return "gpt"
  }
  if (model && isGeminiModel(model)) {
    return "gemini"
  }
  return "default"
}

/**
 * Gets the appropriate Fuxi prompt based on model.
 * GPT models → GPT-5.2 optimized prompt (XML-tagged, principle-driven)
 * Gemini models → Gemini-optimized prompt (aggressive tool-call enforcement, thinking checkpoints)
 * Default (Claude, etc.) → Claude-optimized prompt (modular sections)
 */
export function getFuxiPrompt(model?: string): string {
  // Currently forcing the modular prompt for all models to ensure compliance with Dayu/Fuxi requirements.
  // Model-specific optimizations can be re-introduced later by updating gpt.ts and gemini.ts to use the new modules.
  return FUXI_SYSTEM_PROMPT
}
