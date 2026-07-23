import type { Hooks } from "@opencode-ai/plugin"

/**
 * 压缩上下文保留：会话压缩时把诊断关键状态追加进压缩提示词，
 * 防止长诊断会话压缩后丢失故障描述、当前计划步骤与已采集证据的位置。
 */

export interface DiagnosisContextSnapshot {
  /** 结构化故障描述（fuxi 产出）所在文件 */
  faultDescriptionFile?: string
  /** 当前诊断计划文件（dayu 产出）与执行到的步骤号 */
  planFile?: string
  currentStep?: number
  /** 已产出的报告文件 */
  reportFiles?: string[]
}

export function createCompactionPreserver(args: {
  /** 由调用方提供：sessionID → 诊断状态快照（插件在 tool.execute.after 里维护） */
  snapshotFor: (sessionID: string) => DiagnosisContextSnapshot | undefined
}): NonNullable<Hooks["experimental.session.compacting"]> {
  return async (input, output) => {
    const snapshot = args.snapshotFor(input.sessionID)
    if (!snapshot) return

    const lines: string[] = ["## 诊断会话关键状态（压缩后必须保留）"]
    if (snapshot.faultDescriptionFile) lines.push(`- 故障描述: ${snapshot.faultDescriptionFile}`)
    if (snapshot.planFile) {
      lines.push(
        `- 诊断计划: ${snapshot.planFile}${snapshot.currentStep !== undefined ? `（执行到第 ${snapshot.currentStep} 步）` : ""}`,
      )
    }
    for (const report of snapshot.reportFiles ?? []) lines.push(`- 已产出报告: ${report}`)

    if (lines.length > 1) output.context.push(lines.join("\n"))
  }
}
