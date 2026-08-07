import type { AgentDefinition } from "../types"

import { xuanyuan } from "./xuanyuan"
import { fuxi } from "./fuxi"
import { dayu } from "./dayu"
import { kuafu } from "./kuafu"
import { baize } from "./baize"
import { nuwa } from "./nuwa"
import { taiyi } from "./taiyi"
import { shennong } from "./shennong"

/** 全部诊断 agent 定义（注册顺序 = UI 展示顺序）。 */
export const AGENT_DEFINITIONS: readonly AgentDefinition[] = [
  xuanyuan,
  fuxi,
  dayu,
  kuafu,
  baize,
  nuwa,
  taiyi,
]

/**
 * 神农是 opt-in 的：只有配置了知识库（CASE_KB_ID）且未禁用 case_search 时
 * 才加入注册列表。未启用时它既不注册、也不出现在伏羲的提示词里（见 plugin.ts），
 * 保持与旧版一致的"零感知"降级。
 */
export const OPTIONAL_AGENT_DEFINITIONS: readonly AgentDefinition[] = [shennong]

export { xuanyuan, fuxi, dayu, kuafu, baize, nuwa, taiyi, shennong }
