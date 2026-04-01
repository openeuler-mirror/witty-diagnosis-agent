export const WITTY_INTERNAL_INITIATOR_MARKER = "<!-- WITTY_INTERNAL_INITIATOR -->"

export function createInternalAgentTextPart(text: string): {
  type: "text"
  text: string
} {
  return {
    type: "text",
    text: `${text}\n${WITTY_INTERNAL_INITIATOR_MARKER}`,
  }
}
