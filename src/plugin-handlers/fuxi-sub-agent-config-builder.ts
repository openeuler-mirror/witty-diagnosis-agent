import { FUXI_SUB_PERMISSION, getFuxiSubPrompt } from "../agents/fuxi/fuxi-sub/system-prompt";
import { resolvePromptAppend } from "../agents/builtin-agents/resolve-file-uri";
import { AGENT_MODEL_REQUIREMENTS } from "../shared/model-requirements";
import {
  fetchAvailableModels,
  readConnectedProvidersCache,
  resolveModelPipeline,
} from "../shared";
import { resolveCategoryConfig } from "./category-config-resolver";
import type { CategoryConfig } from "../config/schema/categories";

type FuxiSubOverride = Record<string, unknown> & {
  category?: string;
  model?: string;
  variant?: string;
  reasoningEffort?: string;
  textVerbosity?: string;
  thinking?: { type: string; budgetTokens?: number };
  temperature?: number;
  top_p?: number;
  maxTokens?: number;
  prompt_append?: string;
};

export async function buildFuxiSubAgentConfig(params: {
  configAgentPlan: Record<string, unknown> | undefined;
  pluginFuxiSubOverride: FuxiSubOverride | undefined;
  userCategories: Record<string, CategoryConfig> | undefined;
  currentModel: string | undefined;
}): Promise<Record<string, unknown>> {
  const categoryConfig = params.pluginFuxiSubOverride?.category
    ? resolveCategoryConfig(params.pluginFuxiSubOverride.category, params.userCategories)
    : undefined;

  const requirement = AGENT_MODEL_REQUIREMENTS["fuxi-sub"] || AGENT_MODEL_REQUIREMENTS["fuxi"];
  const connectedProviders = readConnectedProvidersCache();
  const availableModels = await fetchAvailableModels(undefined, {
    connectedProviders: connectedProviders ?? undefined,
  });

  const modelResolution = resolveModelPipeline({
    intent: {
      uiSelectedModel: params.currentModel,
      userModel: params.pluginFuxiSubOverride?.model ?? categoryConfig?.model,
    },
    constraints: { availableModels },
    policy: {
      fallbackChain: requirement?.fallbackChain,
      systemDefaultModel: undefined,
    },
  });

  const resolvedModel = modelResolution?.model;
  const resolvedVariant = modelResolution?.variant;

  const variantToUse = params.pluginFuxiSubOverride?.variant ?? resolvedVariant;
  const reasoningEffortToUse =
    params.pluginFuxiSubOverride?.reasoningEffort ?? categoryConfig?.reasoningEffort;
  const textVerbosityToUse =
    params.pluginFuxiSubOverride?.textVerbosity ?? categoryConfig?.textVerbosity;
  const thinkingToUse = params.pluginFuxiSubOverride?.thinking ?? categoryConfig?.thinking;
  const temperatureToUse =
    params.pluginFuxiSubOverride?.temperature ?? categoryConfig?.temperature;
  const topPToUse = params.pluginFuxiSubOverride?.top_p ?? categoryConfig?.top_p;
  const maxTokensToUse =
    params.pluginFuxiSubOverride?.maxTokens ?? categoryConfig?.maxTokens;

  const base: Record<string, unknown> = {
    ...(resolvedModel ? { model: resolvedModel } : {}),
    ...(variantToUse ? { variant: variantToUse } : {}),
    mode: "subagent",
    prompt: await getFuxiSubPrompt(resolvedModel),
    permission: FUXI_SUB_PERMISSION,
    description: `${(params.configAgentPlan?.description as string) ?? "Plan agent"} (FuxiSub - WittyDiagnosisAgent)`,
    color: (params.configAgentPlan?.color as string) ?? "#FF5722",
    ...(temperatureToUse !== undefined ? { temperature: temperatureToUse } : {}),
    ...(topPToUse !== undefined ? { top_p: topPToUse } : {}),
    ...(maxTokensToUse !== undefined ? { maxTokens: maxTokensToUse } : {}),
    ...(categoryConfig?.tools ? { tools: categoryConfig.tools } : {}),
    ...(thinkingToUse ? { thinking: thinkingToUse } : {}),
    ...(reasoningEffortToUse !== undefined
      ? { reasoningEffort: reasoningEffortToUse }
      : {}),
    ...(textVerbosityToUse !== undefined
      ? { textVerbosity: textVerbosityToUse }
      : {}),
  };

  const override = params.pluginFuxiSubOverride;
  if (!override) return base;

  const { prompt_append, ...restOverride } = override;
  const merged = { ...base, ...restOverride };
  if (prompt_append && typeof merged.prompt === "string") {
    merged.prompt = merged.prompt + "\n" + resolvePromptAppend(prompt_append);
  }
  return merged;
}
