import type { AgentDefinition } from "../types"

/** 伏羲：故障澄清与诊断规划 agent（UI 可见）。仅写 .md，权限只写在本 agent 上。 */
export const fuxi: AgentDefinition = {
  name: "fuxi",
  displayName: "伏羲",
  description:
    "故障澄清与规划：与用户交互补全故障现象、时间线、环境信息，生成诊断排查计划（仅写 .md）",
  descriptionEn:
    "Fault clarification and planning: interacts with the user to complete the symptom, timeline and environment, then produces a diagnostic plan (writes .md only)",
  mode: "all",
  promptFile: "fuxi.md",
  permission: {
    edit: "allow",
    bash: "allow",
    webfetch: "allow",
    question: "allow",
    external_directory: "allow",
    task: "allow",
  },
  mdOnly: true,
  color: "#2980B9",
}
