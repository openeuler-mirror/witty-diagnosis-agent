import { NUWA_PERMISSION, getNuwaPrompt } from "../agents/nuwa/agent";
import { AGENT_LOCALIZATION, l } from "../agents/shared/localization";
import { resolvePromptAppend } from "../agents/builtin-agents/resolve-file-uri";
import { AGENT_MODEL_REQUIREMENTS } from "../shared/model-requirements";
import {
  fetchAvailableModels,
  readConnectedProvidersCache,
  resolveModelPipeline,
} from "../shared";
import { resolveCategoryConfig } from "./category-config-resolver";
import type { CategoryConfig } from "../config/schema/categories";

type NuwaOverride = Record<string, unknown> & {
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

export async function buildNuwaAgentConfig(params: {
  configAgentPlan: Record<string, unknown> | undefined;
  pluginNuwaOverride: NuwaOverride | undefined;
  userCategories: Record<string, CategoryConfig> | undefined;
  currentModel: string | undefined;
  outputLanguage: "zh" | "en";
}): Promise<Record<string, unknown>> {
  const categoryConfig = params.pluginNuwaOverride?.category
    ? resolveCategoryConfig(params.pluginNuwaOverride.category, params.userCategories)
    : undefined;

  const requirement = AGENT_MODEL_REQUIREMENTS["nuwa"];
  const connectedProviders = readConnectedProvidersCache();
  const availableModels = await fetchAvailableModels(undefined, {
    connectedProviders: connectedProviders ?? undefined,
  });

  const modelResolution = resolveModelPipeline({
    intent: {
      uiSelectedModel: params.currentModel,
      userModel: params.pluginNuwaOverride?.model ?? categoryConfig?.model,
    },
    constraints: { availableModels },
    policy: {
      fallbackChain: requirement?.fallbackChain,
      systemDefaultModel: undefined,
    },
  });

  const resolvedModel = modelResolution?.model;
  const resolvedVariant = modelResolution?.variant;

  const variantToUse = params.pluginNuwaOverride?.variant ?? resolvedVariant;
  const reasoningEffortToUse =
    params.pluginNuwaOverride?.reasoningEffort ?? categoryConfig?.reasoningEffort;
  const textVerbosityToUse =
    params.pluginNuwaOverride?.textVerbosity ?? categoryConfig?.textVerbosity;
  const thinkingToUse = params.pluginNuwaOverride?.thinking ?? categoryConfig?.thinking;
  const temperatureToUse =
    params.pluginNuwaOverride?.temperature ?? categoryConfig?.temperature;
  const topPToUse = params.pluginNuwaOverride?.top_p ?? categoryConfig?.top_p;
  const maxTokensToUse =
    params.pluginNuwaOverride?.maxTokens ?? categoryConfig?.maxTokens;

  const base: Record<string, unknown> = {
    ...(resolvedModel ? { model: resolvedModel } : {}),
    ...(variantToUse ? { variant: variantToUse } : {}),
    mode: "all",
    prompt: await getNuwaPrompt(params.outputLanguage),
    permission: NUWA_PERMISSION,
    description: `${(params.configAgentPlan?.description as string) ?? l(AGENT_LOCALIZATION["nuwa"].description, params.outputLanguage)}`,
    color: (params.configAgentPlan?.color as string) ?? "#22C55E",
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

  const override = params.pluginNuwaOverride;
  if (!override) return base;

  const { prompt_append, ...restOverride } = override;
  const merged = { ...base, ...restOverride };
  if (prompt_append && typeof merged.prompt === "string") {
    merged.prompt = merged.prompt + "\n" + resolvePromptAppend(prompt_append);
  }
  return merged;
}
