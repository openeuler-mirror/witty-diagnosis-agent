import { getAgentConfigKey } from "../shared/agent-display-names"

/** Xuanyuan/Fuxi：主界面；build：OpenCode 原生 Build 模式，需与上游一致在 UI 中可选 */
const UI_VISIBLE_AGENT_KEYS = new Set(["xuanyuan", "fuxi", "build"])

export function applyUiAgentVisibility(
  agents: Record<string, unknown>,
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(agents).map(([key, value]) => {
      const agentConfigKey = getAgentConfigKey(key)
      if (UI_VISIBLE_AGENT_KEYS.has(agentConfigKey)) {
        return [key, value]
      }

      if (!value || typeof value !== "object" || Array.isArray(value)) {
        return [key, value]
      }

      return [
        key,
        {
          ...value,
          mode: "subagent",
          hidden: true,
        },
      ]
    }),
  )
}
