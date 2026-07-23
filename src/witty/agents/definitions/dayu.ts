import type { AgentDefinition } from "../types"

/**
 * 大禹：诊断编排调度 agent。仅作为 subagent 被 xuanyuan 委派，UI 主列表隐藏。
 * 权限只写在本 agent 上（不做全局兜底，避免影响其他插件的 agent）。
 */
export const dayu: AgentDefinition = {
  name: "dayu",
  displayName: "大禹",
  description:
    "诊断编排调度：基于 Plan 或临时请求构建诊断任务集，经 task 委派 Kuafu 并行执行并汇总结果（仅写 .md）",
  mode: "subagent",
  hidden: true,
  promptFile: "dayu.md",
  permission: {
    edit: "allow",
    bash: "allow",
    webfetch: "allow",
    question: "allow",
    external_directory: "allow",
    task: "allow",
  },
  mdOnly: true,
  color: "#16A085",
}
