import type { PipelineStage } from "./types"

/**
 * 标准诊断流水线（xuanyuan 编排下的阶段顺序）。
 *
 * 注意：这只是缺省阶段表——xuanyuan 的提示词允许其按故障类型裁剪
 * （如离线分析跳过 clarify、健康巡检跳过 remediate）。
 */
export const DIAGNOSIS_PIPELINE: readonly PipelineStage[] = [
  { agent: "fuxi", role: "clarify", optional: true },
  { agent: "dayu", role: "plan" },
  { agent: "kuafu", role: "execute" },
  { agent: "baize", role: "report" },
  { agent: "nuwa", role: "remediate", optional: true },
  { agent: "taiyi", role: "qa", optional: true },
]
