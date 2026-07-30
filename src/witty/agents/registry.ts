import type { AgentConfig } from "@opencode-ai/sdk"

import type { AgentOverride, OutputLanguage, ResolvedWittyConfig } from "../config/types"
import type { AgentDefinition } from "./types"
import { WITTY_AGENT_NAMES } from "./types"
import { loadAgentPrompt, type PromptContext } from "./prompt-loader"
import { log } from "../shared/log"

/** 本插件拥有的 agent key 集合。只有这些 key 才允许 witty 写入/覆盖。 */
const WITTY_OWNED_KEYS: ReadonlySet<string> = new Set(WITTY_AGENT_NAMES)

/**
 * Agent 注册器：把 AgentDefinition + 用户覆盖编译成 OpenCode 的 Config.agent 表。
 *
 * - 注册键 = definition.name（裸名），供原生 task 委派命中。
 * - hidden=true 的 agent（dayu/kuafu/baize/nuwa）设 mode:subagent + hidden，
 *   只能被委派、不在 UI 主列表出现；只暴露 xuanyuan/fuxi/taiyi。
 * - 权限逐 agent 写在 permission 上，不做全局兜底，不影响其他插件的 agent。
 * - 语言：description 与提示词按 output_language 选择。
 */

export function buildAgentConfig(
  definition: AgentDefinition,
  override: AgentOverride | undefined,
  promptContext: PromptContext,
): AgentConfig {
  const lang = promptContext.language
  const description =
    lang === "en" && definition.descriptionEn ? definition.descriptionEn : definition.description

  const config: Record<string, unknown> = {
    description: `${definition.displayName} · ${description}`,
    mode: definition.mode,
    prompt: loadAgentPrompt(definition, {
      ...promptContext,
      extraInstructions: override?.extra_instructions,
    }),
  }
  if (definition.hidden) config["hidden"] = true
  if (definition.permission) config["permission"] = definition.permission
  if (definition.color) config["color"] = definition.color
  if (definition.tools) config["tools"] = definition.tools
  if (definition.temperature !== undefined) config["temperature"] = definition.temperature
  if (definition.maxTokens !== undefined) config["maxTokens"] = definition.maxTokens

  const model = override?.model ?? definition.defaultModel
  if (model) config["model"] = model

  return config as AgentConfig
}

/**
 * 记录本插件上一轮往 config.agent 注入过的 key（跨 config 钩子多次调用保持）。
 * config 钩子可能被多次触发；用它区分「这个 key 是 witty 自己注入的（可刷新）」
 * 与「这个 key 是其他插件/用户注册的（必须让位、绝不覆盖）」。
 * 不往 config 里写任何私有标记，避免污染 OpenCode 的 agent schema。
 */
const wittyInjectedKeys = new Set<string>()

/**
 * 该 agent 名是否确实由本插件注册。
 *
 * 判断依据是「名字属于本插件 **且** 本插件真的注入成功了」两个条件的合取：
 * applyAgentsToConfig 在同名 key 已被其他插件/用户占用时会让位（见上），
 * 此时 "fuxi" 这个名字跑的是别人的 agent，只查 WITTY_AGENT_NAMES 会误判成自己的。
 *
 * 供需要「仅对本插件 agent 生效」的钩子做范围限定，避免影响其他插件的 agent。
 */
export function isWittyOwnedAgent(agentName: string | undefined): boolean {
  if (agentName === undefined) return false
  return WITTY_OWNED_KEYS.has(agentName) && wittyInjectedKeys.has(agentName)
}

export function applyAgentsToConfig(args: {
  /** OpenCode 的 Config 对象（config 钩子入参），此处只关心 agent 表 */
  target: { agent?: Record<string, AgentConfig | undefined> }
  definitions: readonly AgentDefinition[]
  pluginConfig: ResolvedWittyConfig
  promptContext: Omit<PromptContext, "language">
}): void {
  const { target, definitions, pluginConfig, promptContext } = args
  const language: OutputLanguage = pluginConfig.output_language
  const disabled = new Set(pluginConfig.disabled_agents.map((n) => n.toLowerCase()))

  target.agent ??= {}
  for (const definition of definitions) {
    // 铁律：只写本插件拥有的 key。非 WITTY_OWNED_KEYS 的键（其他插件/用户/内置
    // 的 agent）本函数一律不读、不改、不删——这保证绝不覆盖其他插件的 agent。
    if (!WITTY_OWNED_KEYS.has(definition.name)) continue

    const override = pluginConfig.agents[definition.name]
    if (disabled.has(definition.name) || override?.disable) {
      log("registry: agent 已禁用", { agent: definition.name })
      continue
    }
    // 该 key 已被占用，且不是本插件上一轮注入的 → 是其他插件/用户先注册的同名 agent，让位。
    const occupiedByOther =
      target.agent[definition.name] !== undefined && !wittyInjectedKeys.has(definition.name)
    if (occupiedByOther) {
      log("registry: 同名 agent 已被其他来源占用，让位不覆盖", { agent: definition.name })
      continue
    }
    target.agent[definition.name] = buildAgentConfig(definition, override, {
      ...promptContext,
      language,
    })
    wittyInjectedKeys.add(definition.name)
  }
}
