import type { AgentConfig } from "@opencode-ai/sdk"
import type { AgentOverrideConfig } from "../agents/types"
import { createBaizeAgent } from "../agents/baize/index"
import { AGENT_MODEL_REQUIREMENTS } from "../shared/model-requirements"
import {
  fetchAvailableModels,
  readConnectedProvidersCache,
  resolveModelPipeline,
} from "../shared"

export interface BuildBaizeAgentConfigParams {
  /** Plugin-level Baize override from witty-diagnosis-agent config (if any) */
  pluginBaizeOverride?: AgentOverrideConfig
  /** Currently selected UI model, if any */
  currentModel?: string
}

/**
 * Builds the Baize agent config by combining:
 * - Model resolution based on AGENT_MODEL_REQUIREMENTS["baize"]
 * - Base Baize agent (deep worker, Hephaestus-style)
 * - Plugin-level overrides from config
 */
export async function buildBaizeAgentConfig(
  params: BuildBaizeAgentConfigParams,
): Promise<AgentConfig> {
  const { pluginBaizeOverride, currentModel } = params

  const requirement = AGENT_MODEL_REQUIREMENTS["baize"]
  const connectedProviders = readConnectedProvidersCache()
  const availableModels = await fetchAvailableModels(undefined, {
    connectedProviders: connectedProviders ?? undefined,
  })

  const modelResolution = resolveModelPipeline({
    intent: {
      uiSelectedModel: currentModel,
      userModel: pluginBaizeOverride?.model,
    },
    constraints: { availableModels },
    policy: {
      fallbackChain: requirement?.fallbackChain,
      systemDefaultModel: undefined,
    },
  })

  const resolvedModel = modelResolution?.model
  const resolvedVariant = modelResolution?.variant

  const variantToUse = pluginBaizeOverride?.variant ?? resolvedVariant

  const baseConfig = createBaizeAgent(
    pluginBaizeOverride?.model ?? resolvedModel ?? currentModel
  )

  if (!pluginBaizeOverride) {
    return {
      ...baseConfig,
      ...(variantToUse ? { variant: variantToUse } : {}),
    }
  }

  const { model: _ignoredModel, variant: _ignoredVariant, ...restOverride } =
    pluginBaizeOverride

  return {
    ...baseConfig,
    ...(variantToUse ? { variant: variantToUse } : {}),
    ...restOverride,
  }
}
