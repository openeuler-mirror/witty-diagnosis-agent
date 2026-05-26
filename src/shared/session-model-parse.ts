import type { SessionModel } from "./session-model-state"

/** Parse OpenCode session `model` field (string or { providerID, modelID }). */
export function parseSessionModelField(model: unknown): SessionModel | undefined {
  if (typeof model === "string") {
    const parts = model.split("/")
    if (parts.length < 2) return undefined
    return { providerID: parts[0], modelID: parts.slice(1).join("/") }
  }
  if (typeof model === "object" && model !== null) {
    const o = model as Record<string, unknown>
    const pRaw = o.providerID ?? o.providerId ?? o.provider
    const midRaw = o.modelID ?? o.modelId ?? o.id
    if (typeof pRaw === "string" && typeof midRaw === "string") {
      return { providerID: pRaw, modelID: midRaw }
    }
  }
  return undefined
}
