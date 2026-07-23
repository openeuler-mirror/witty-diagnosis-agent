import type { WittyAgentName } from "../agents/types"

/**
 * 诊断流水线阶段（纯数据参考）。
 *
 * 实际的子代理委派由 OpenCode 原生 task 工具执行，xuanyuan 提示词按此阶段表
 * 驱动调用；本文件不含委派实现，仅供文档与未来编排校验参考。
 */
export interface PipelineStage {
  agent: WittyAgentName
  role: "clarify" | "plan" | "execute" | "report" | "remediate" | "qa"
  /** 可跳过（如用户已提供完整故障描述则跳过 clarify） */
  optional?: boolean
}
