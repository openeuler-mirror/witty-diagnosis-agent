import type { AgentDefinition } from "../types"

import { xuanyuan } from "./xuanyuan"
import { fuxi } from "./fuxi"
import { dayu } from "./dayu"
import { kuafu } from "./kuafu"
import { baize } from "./baize"
import { nuwa } from "./nuwa"
import { taiyi } from "./taiyi"

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

export { xuanyuan, fuxi, dayu, kuafu, baize, nuwa, taiyi }
