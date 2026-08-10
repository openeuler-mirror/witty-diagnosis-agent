import path from "node:path"
import os from "node:os"

import type { ResolvedWittyConfig } from "./types"
import { wittyConfigSchema } from "./schema"
import { readJsoncFile } from "../shared/jsonc"
import { log } from "../shared/log"

const CONFIG_BASENAME = "witty-diagnosis-agent"

/** 配置发现顺序：项目级覆盖用户级，字段级浅合并（agents 表做键级合并）。 */
export function candidateConfigPaths(projectDir: string): string[] {
  const home = os.homedir()
  return [
    path.join(home, ".config", "opencode", `${CONFIG_BASENAME}.jsonc`),
    path.join(home, ".config", "opencode", `${CONFIG_BASENAME}.json`),
    path.join(projectDir, ".opencode", `${CONFIG_BASENAME}.jsonc`),
    path.join(projectDir, ".opencode", `${CONFIG_BASENAME}.json`),
  ]
}

/**
 * 加载并合并配置，Zod 校验后填充默认值。
 * 任一文件解析失败：记日志、跳过该文件，不让插件加载失败。
 */
export function loadWittyConfig(projectDir: string): ResolvedWittyConfig {
  let merged: Record<string, unknown> = {}

  for (const file of candidateConfigPaths(projectDir)) {
    const raw = readJsoncFile(file)
    if (raw === undefined) continue
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
      log("config: 忽略非对象配置文件", { file })
      continue
    }
    merged = mergeConfigLayer(merged, raw as Record<string, unknown>)
    log("config: 已合并配置层", { file })
  }

  const parsed = wittyConfigSchema.safeParse(merged)
  if (!parsed.success) {
    log("config: 校验失败，回退默认配置", { issues: parsed.error.issues })
    return wittyConfigSchema.parse({})
  }
  return parsed.data
}

/** 浅合并；agents 表按键合并，disabled_agents / disabled_mcps 取并集。 */
function mergeConfigLayer(
  base: Record<string, unknown>,
  layer: Record<string, unknown>,
): Record<string, unknown> {
  const result: Record<string, unknown> = { ...base, ...layer }

  const baseAgents = asRecord(base["agents"])
  const layerAgents = asRecord(layer["agents"])
  if (baseAgents && layerAgents) result["agents"] = { ...baseAgents, ...layerAgents }

  const baseDisabled = asStringArray(base["disabled_agents"])
  const layerDisabled = asStringArray(layer["disabled_agents"])
  if (baseDisabled && layerDisabled) {
    result["disabled_agents"] = [...new Set([...baseDisabled, ...layerDisabled])]
  }

  const baseDisabledMcps = asStringArray(base["disabled_mcps"])
  const layerDisabledMcps = asStringArray(layer["disabled_mcps"])
  if (baseDisabledMcps && layerDisabledMcps) {
    result["disabled_mcps"] = [...new Set([...baseDisabledMcps, ...layerDisabledMcps])]
  }
  return result
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined
}

function asStringArray(value: unknown): string[] | undefined {
  return Array.isArray(value) && value.every((v) => typeof v === "string")
    ? (value as string[])
    : undefined
}
