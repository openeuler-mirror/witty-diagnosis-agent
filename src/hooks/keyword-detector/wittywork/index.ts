import { WITTYWORK_MODE_MESSAGE } from "./message"

export const WITTYWORK_MODE_PATTERN = /\bwittywork\b/i

export function getWittyworkModeMessage(agentName?: string, _modelID?: string): string {
  // 仅在 Fuxi 相关会话中启用 wittywork 模式，其它 agent 忽略该提示。
  if (!agentName) {
    return ""
  }

  const lowerName = agentName.toLowerCase()
  if (!lowerName.includes("fuxi")) {
    return ""
  }

  return WITTYWORK_MODE_MESSAGE
}
