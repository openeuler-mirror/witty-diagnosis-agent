import type { AgentDefinition } from "../types"

/**
 * 夸父：诊断执行 agent。仅作为 subagent 被 dayu 委派，UI 主列表隐藏。
 *
 * 必须放行 external_directory 与 bash：诊断采集常读工作区外的日志，OpenCode 权限
 * 基线里 external_directory 默认 "ask"，而 subagent 子会话的询问弹不到主会话会死等。
 * 权限只写在本 agent 上，不做全局兜底，避免影响其他插件的 agent。
 */
export const kuafu: AgentDefinition = {
  name: "kuafu",
  displayName: "夸父",
  description:
    "诊断执行：按诊断计划逐步执行采集与分析命令，记录证据链，遇到分支按计划判定走向",
  mode: "subagent",
  hidden: true,
  promptFile: "kuafu.md",
  temperature: 0.1,
  permission: {
    bash: "allow",
    edit: "allow",
    webfetch: "allow",
    external_directory: "allow",
    task: "deny",
  },
  color: "#F97316",
}
