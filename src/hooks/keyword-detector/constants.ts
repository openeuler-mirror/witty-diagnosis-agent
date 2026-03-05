export const CODE_BLOCK_PATTERN = /```[\s\S]*?```/g
export const INLINE_CODE_PATTERN = /`[^`]+`/g

// Re-export from submodules
export { isPlannerAgent, getUltraworkMessage } from "./ultrawork"
export { WITTYWORK_MODE_PATTERN, getWittyworkModeMessage } from "./wittywork"
export { SEARCH_PATTERN, SEARCH_MESSAGE } from "./search"
export { ANALYZE_PATTERN, ANALYZE_MESSAGE } from "./analyze"

import { getUltraworkMessage } from "./ultrawork"
import { WITTYWORK_MODE_PATTERN, getWittyworkModeMessage } from "./wittywork"
import { SEARCH_PATTERN, SEARCH_MESSAGE } from "./search"
import { ANALYZE_PATTERN, ANALYZE_MESSAGE } from "./analyze"

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
    pattern: WITTYWORK_MODE_PATTERN,
    message: getWittyworkModeMessage,
  },
  {
    pattern: SEARCH_PATTERN,
    message: SEARCH_MESSAGE,
  },
  {
    pattern: ANALYZE_PATTERN,
    message: ANALYZE_MESSAGE,
  },
]
