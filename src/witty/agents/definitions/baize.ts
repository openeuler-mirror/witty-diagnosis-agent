import type { AgentDefinition } from "../types"

/**
 * 白泽：RCA 报告生成 agent。仅作为 subagent 被委派，UI 主列表隐藏。
 * 需读工作区外的证据文件并写报告，放行 external_directory/edit/bash。
 */
export const baize: AgentDefinition = {
  name: "baize",
  displayName: "白泽",
  description:
    "报告生成：汇总证据链产出根因分析（RCA）报告，输出到报告目录，支持 md/html 双格式",
  mode: "subagent",
  hidden: true,
  promptFile: "baize.md",
  permission: {
    edit: "allow",
    bash: "allow",
    webfetch: "allow",
    question: "allow",
    external_directory: "allow",
    task: "deny",
  },
  maxTokens: 32000,
  color: "#0D9488",
}
