import type { AgentDefinition } from "../types"

/**
 * 女娲：修复方案 agent。仅作为 subagent 被 xuanyuan 委派，UI 主列表隐藏。
 * 修复操作需 bash/edit 与跨目录访问；question 放行以支持修复确认交互。
 */
export const nuwa: AgentDefinition = {
  name: "nuwa",
  displayName: "女娲",
  description:
    "修复建议：基于根因给出即时止血、根治与预防三级方案，含操作步骤、风险提示与回滚方法",
  mode: "subagent",
  hidden: true,
  promptFile: "nuwa.md",
  permission: {
    bash: "allow",
    edit: "allow",
    webfetch: "allow",
    question: "allow",
    external_directory: "allow",
    task: "deny",
  },
  color: "#27AE60",
}
