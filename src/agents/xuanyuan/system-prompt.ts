import { XUANYUAN_IDENTITY_CONSTRAINTS } from "./identity-constraints"
import { XUANYUAN_BEHAVIORAL_SUMMARY } from "./behavioral-summary"
import { getSharedEnvPrompt } from "../shared-env-prompt"

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

export async function getXuanyuanPrompt(model?: string): Promise<string> {
  void model
  const extraPrompt = await getSharedEnvPrompt()
  return XUANYUAN_SYSTEM_PROMPT + extraPrompt
}
