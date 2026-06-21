import type { AgentConfig } from "@opencode-ai/sdk"
import type { AgentOverrideConfig } from "../agents/types"
import {
  createTaiyiAgent,
  TAIYI_AGENT_NAME,
} from "../agents/taiyi/qa-agent"
import { AGENT_MODEL_REQUIREMENTS } from "../shared/model-requirements"
import {
  fetchAvailableModels,
  readConnectedProvidersCache,
  resolveModelPipeline,
} from "../shared"

export interface BuildTaiyiAgentConfigParams {
  /** Plugin-level override from witty-diagnosis-agent config (if any) */
  pluginTaiyiOverride?: AgentOverrideConfig
  /** Currently selected UI model, if any */
  currentModel?: string
  outputLanguage: "zh" | "en"
}

export async function buildTaiyiAgentConfig(
  params: BuildTaiyiAgentConfigParams,
): Promise<AgentConfig> {
  const { pluginTaiyiOverride, currentModel } = params

  const requirement = AGENT_MODEL_REQUIREMENTS[TAIYI_AGENT_NAME]
  const connectedProviders = readConnectedProvidersCache()
  const availableModels = await fetchAvailableModels(undefined, {
    connectedProviders: connectedProviders ?? undefined,
  })

  const modelResolution = resolveModelPipeline({
    intent: {
      uiSelectedModel: currentModel,
      userModel: pluginTaiyiOverride?.model,
    },
    constraints: { availableModels },
    policy: {
      fallbackChain: requirement?.fallbackChain,
      systemDefaultModel: undefined,
    },
  })

  const resolvedModel = modelResolution?.model
  const resolvedVariant = modelResolution?.variant
  const variantToUse = pluginTaiyiOverride?.variant ?? resolvedVariant

  const baseConfig = createTaiyiAgent(
    pluginTaiyiOverride?.model ?? resolvedModel ?? currentModel,
    params.outputLanguage,
    { enableWebSearch: false },
  )

  if (!pluginTaiyiOverride) {
    return {
      ...baseConfig,
      ...(variantToUse ? { variant: variantToUse } : {}),
    }
  }

  const { model: _ignoredModel, variant: _ignoredVariant, ...restOverride } =
    pluginTaiyiOverride

  return {
    ...baseConfig,
    ...(variantToUse ? { variant: variantToUse } : {}),
    ...restOverride,
  }
}
