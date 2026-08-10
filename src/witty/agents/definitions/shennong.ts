import type { AgentDefinition } from "../types"

/**
 * 神农：已知问题案例检索 sub-agent（opt-in）。
 *
 * 只读检索：调用 case_search MCP 的 `search_jsons` 检索知识库已知问题案例，
 * 只回传落盘文件路径 cases_file + 案例 id/name，不读正文、不下根因结论。
 *
 * - hidden：纯 subagent，不进 UI 选择器，只能被 fuxi 通过 task 委派。
 * - bash 需 allow：委派 euler-rag-json-search skill 子 agent 时要用到。
 * - 仅当 CASE_KB_ID 配置且 case_search 未禁用时才注册（见 registry / plugin）。
 */
export const shennong: AgentDefinition = {
  name: "shennong",
  displayName: "神农",
  description:
    "已知问题分析：检索知识库中的相似历史案例，回传案例文件路径与案例名，供伏羲规划参考；只读，不下根因结论",
  descriptionEn:
    "Known-issue analysis: retrieves similar historical cases from the knowledge base and returns the case file path plus case names for Fuxi's planning; read-only, draws no root-cause conclusions",
  mode: "subagent",
  promptFile: "shennong.md",
  hidden: true,
  permission: {
    edit: "deny",
    bash: "allow",
    webfetch: "deny",
    task: "allow",
  },
  color: "#8E7CC3",
}
