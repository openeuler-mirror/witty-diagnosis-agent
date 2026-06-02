import { getAgentConfigKey } from "../shared/agent-display-names"

/** 本项目所属的所有 agent keys（包含 build 以防误判） */
const WITTY_OWNED_AGENT_KEYS = new Set([
  "xuanyuan",
  "fuxi",
  "fuxi-sub",
  "nuwa",
  "nuwa-sub",
  "dayu",
  "baize",
  "kuafu",
  "multimodal-looker",
  "build"
])

/** Xuanyuan/Fuxi：主界面；build：OpenCode 原生 Build 模式，需与上游一致在 UI 中可选 */
const UI_VISIBLE_AGENT_KEYS = new Set(["xuanyuan", "fuxi", "build"])

export function applyUiAgentVisibility(
  agents: Record<string, unknown>,
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(agents).map(([key, value]) => {
      const agentConfigKey = getAgentConfigKey(key)

      // 只对本插件所属的 Agent 进行 UI 可见性约束控制。
      // 对于不属于本插件的（例如用户配置的其他插件的 Agent），直接放行，不添加 hidden 属性。
      if (!WITTY_OWNED_AGENT_KEYS.has(agentConfigKey)) {
        return [key, value]
      }

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
