import { FUXI_AGENT } from "./constants"

export function isFuxiAgent(agentName: string | undefined): boolean {
  return agentName?.toLowerCase().includes(FUXI_AGENT) ?? false
}
