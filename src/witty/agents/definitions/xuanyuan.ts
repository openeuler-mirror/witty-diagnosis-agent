import type { AgentDefinition } from "../types"

/** 轩辕：诊断总编排 agent（用户主入口，UI 可见）。权限只写在本 agent 上。 */
export const xuanyuan: AgentDefinition = {
  name: "xuanyuan",
  displayName: "轩辕",
  description:
    "诊断总编排：接收故障描述，驱动澄清→规划→执行→报告→修复建议全流程，按需调度其余诊断 agent",
  descriptionEn:
    "Diagnosis controller: takes the fault description and drives the full pipeline (clarify → plan → execute → report → remediation), delegating to the other diagnostic agents as needed",
  mode: "all",
  promptFile: "xuanyuan.md",
  permission: {
    task: "allow",
    edit: "allow",
    bash: "allow",
    webfetch: "allow",
    question: "allow",
    external_directory: "allow",
    report_visualization: "allow",
  },
  color: "#2196F3",
}
