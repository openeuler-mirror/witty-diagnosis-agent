import { AUTO_DIAG_MODE_MESSAGE } from "./message"

export const AUTO_DIAG_MODE_PATTERN = /\bauto-diag\b/i

export function getAutoDiagModeMessage(agentName?: string, _modelID?: string): string {
  // 仅在 Fuxi 相关会话中启用 auto-diag 模式，其它 agent 忽略该提示。
  if (!agentName) {
    return ""
  }

  const lowerName = agentName.toLowerCase()
  if (!lowerName.includes("fuxi")) {
    return ""
  }

  return AUTO_DIAG_MODE_MESSAGE
}
