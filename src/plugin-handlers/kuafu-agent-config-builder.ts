import type { AgentConfig } from "@opencode-ai/sdk"
import type { AgentOverrideConfig } from "../agents/types"
import { createKuafuAgent } from "../agents/kuafu"

export interface BuildKuafuAgentConfigParams {
  /** Plugin-level Kuafu override from witty-diagnosis-agent config (if any) */
  pluginKuafuOverride?: AgentOverrideConfig
  /** Currently selected UI model, if any */
  currentModel?: string
}

/**
 * Builds the Kuafu agent config by combining the base Kuafu agent
 * with any plugin-level overrides.
 *
 * Kuafu is a general diagnostic executor, typically used as a subagent.
 * Model selection is simple: prefer explicit override model, then UI model.
 */
export async function buildKuafuAgentConfig(
  params: BuildKuafuAgentConfigParams
): Promise<AgentConfig> {
  const { pluginKuafuOverride, currentModel } = params

  const baseModel = (pluginKuafuOverride?.model as string | undefined) ?? currentModel

  const baseConfig = await createKuafuAgent(
    baseModel ? { model: baseModel } : {}
  )

  if (!pluginKuafuOverride) {
    return baseConfig
  }

  const {
    // handled above
    model: _ignoredModel,
    // remaining override fields merge directly onto AgentConfig
    ...restOverride
  } = pluginKuafuOverride

  return {
    ...baseConfig,
    ...restOverride,
  }
}

