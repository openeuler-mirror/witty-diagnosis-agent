export const CODE_BLOCK_PATTERN = /```[\s\S]*?```/g
export const INLINE_CODE_PATTERN = /`[^`]+`/g

// Re-export from submodules
export { isPlannerAgent, getUltraworkMessage } from "./ultrawork"
export { AUTO_DIAG_MODE_PATTERN, getAutoDiagModeMessage } from "./auto-diag"
export { SEARCH_PATTERN, SEARCH_MESSAGE } from "./search"

import { getUltraworkMessage } from "./ultrawork"
import { AUTO_DIAG_MODE_PATTERN, getAutoDiagModeMessage } from "./auto-diag"
import { SEARCH_PATTERN, SEARCH_MESSAGE } from "./search"

export type KeywordDetector = {
  pattern: RegExp
  message: string | ((agentName?: string, modelID?: string) => string)
}

export const KEYWORD_DETECTORS: KeywordDetector[] = [
  {
    pattern: /\b(ultrawork|ulw)\b/i,
    message: getUltraworkMessage,
  },
  {
    pattern: AUTO_DIAG_MODE_PATTERN,
    message: getAutoDiagModeMessage,
  },
  {
    pattern: SEARCH_PATTERN,
    message: SEARCH_MESSAGE,
  },
]
