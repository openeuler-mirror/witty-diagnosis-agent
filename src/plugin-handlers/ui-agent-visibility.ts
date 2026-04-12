import { getAgentConfigKey } from "../shared/agent-display-names"

const UI_VISIBLE_AGENT_KEYS = new Set(["xuanyuan", "fuxi"])

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
