import {
  AUTO_SLASH_COMMAND_TAG_CLOSE,
  AUTO_SLASH_COMMAND_TAG_OPEN,
} from "../hooks/auto-slash-command/constants"

/** Concatenate text parts (same idea as chat.message extractPromptText). */
export function extractPromptTextFromParts(parts: Array<{ type: string; text?: string }>): string {
  return parts
    .filter((p) => p.type === "text")
    .map((p) => p.text || "")
    .join(" ")
    .trim()
}

/** Strip auto-slash wrapper so inner `/start-dayu` or template is visible. */
export function stripAutoSlashTaggedContent(text: string): string {
  let t = text.trim()
  if (t.includes(AUTO_SLASH_COMMAND_TAG_OPEN) && t.includes(AUTO_SLASH_COMMAND_TAG_CLOSE)) {
    const start = t.indexOf(AUTO_SLASH_COMMAND_TAG_OPEN) + AUTO_SLASH_COMMAND_TAG_OPEN.length
    const end = t.indexOf(AUTO_SLASH_COMMAND_TAG_CLOSE)
    if (end > start) {
      t = t.slice(start, end).trim()
    }
  }
  return t
}

export function isModelInheritanceSlashCommand(promptText: string): boolean {
  return /^\/(start-dayu|start-baize|witty-diag)\b/i.test(promptText.trim())
}

export function isModelInheritanceCommandTemplate(promptText: string): boolean {
  return /you are switching this session to the (dayu|baize|xuanyuan) agent\./i.test(promptText)
}

/**
 * User message is a model-inheriting slash or expanded template. OpenCode may attach the
 * *target agent's default model* on this message; we must not copy that into session map or it
 * overwrites the prior agent's (e.g. Fuxi glm) before chat.message inheritance runs.
 */
export function isModelInheritanceUserPrompt(rawText: string): boolean {
  const inner = stripAutoSlashTaggedContent(rawText)
  return isModelInheritanceSlashCommand(inner) || isModelInheritanceCommandTemplate(inner)
}

export function getInheritanceTargetAgentKey(promptText: string): string | undefined {
  const trimmed = stripAutoSlashTaggedContent(promptText).trim()
  const slash = /^\/(start-dayu|start-baize|witty-diag)\b/i.exec(trimmed)
  if (slash) {
    const cmd = slash[1].toLowerCase()
    if (cmd === "start-dayu") return "dayu"
    if (cmd === "start-baize") return "baize"
    if (cmd === "witty-diag") return "xuanyuan"
  }
  const tmpl = /you are switching this session to the (dayu|baize|xuanyuan) agent\./i.exec(trimmed)
  if (tmpl) return tmpl[1].toLowerCase()
  return undefined
}
