import { NUWA_SUB_PERMISSION, getNuwaSubPrompt } from "../agents/nuwa/agent";
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

type NuwaSubOverride = Record<string, unknown> & {
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

export async function buildNuwaSubAgentConfig(params: {
  configAgentPlan: Record<string, unknown> | undefined;
  pluginNuwaSubOverride: NuwaSubOverride | undefined;
  userCategories: Record<string, CategoryConfig> | undefined;
  currentModel: string | undefined;
  outputLanguage: "zh" | "en";
}): Promise<Record<string, unknown>> {
  const categoryConfig = params.pluginNuwaSubOverride?.category
    ? resolveCategoryConfig(params.pluginNuwaSubOverride.category, params.userCategories)
    : undefined;

  const requirement = AGENT_MODEL_REQUIREMENTS["nuwa-sub"] || AGENT_MODEL_REQUIREMENTS["nuwa"];
  const connectedProviders = readConnectedProvidersCache();
  const availableModels = await fetchAvailableModels(undefined, {
    connectedProviders: connectedProviders ?? undefined,
  });

  const modelResolution = resolveModelPipeline({
    intent: {
      uiSelectedModel: params.currentModel,
      userModel: params.pluginNuwaSubOverride?.model ?? categoryConfig?.model,
    },
    constraints: { availableModels },
    policy: {
      fallbackChain: requirement?.fallbackChain,
      systemDefaultModel: undefined,
    },
  });

  const resolvedModel = modelResolution?.model;
  const resolvedVariant = modelResolution?.variant;

  const variantToUse = params.pluginNuwaSubOverride?.variant ?? resolvedVariant;
  const reasoningEffortToUse =
    params.pluginNuwaSubOverride?.reasoningEffort ?? categoryConfig?.reasoningEffort;
  const textVerbosityToUse =
    params.pluginNuwaSubOverride?.textVerbosity ?? categoryConfig?.textVerbosity;
  const thinkingToUse = params.pluginNuwaSubOverride?.thinking ?? categoryConfig?.thinking;
  const temperatureToUse =
    params.pluginNuwaSubOverride?.temperature ?? categoryConfig?.temperature;
  const topPToUse = params.pluginNuwaSubOverride?.top_p ?? categoryConfig?.top_p;
  const maxTokensToUse =
    params.pluginNuwaSubOverride?.maxTokens ?? categoryConfig?.maxTokens;

  const base: Record<string, unknown> = {
    ...(resolvedModel ? { model: resolvedModel } : {}),
    ...(variantToUse ? { variant: variantToUse } : {}),
    mode: "subagent",
    prompt: await getNuwaSubPrompt(params.outputLanguage),
    permission: NUWA_SUB_PERMISSION,
    description: `${(params.configAgentPlan?.description as string) ?? l(AGENT_LOCALIZATION["nuwa-sub"] || AGENT_LOCALIZATION["nuwa"], params.outputLanguage)}`,
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

  const override = params.pluginNuwaSubOverride;
  if (!override) return base;

  const { prompt_append, ...restOverride } = override;
  const merged = { ...base, ...restOverride };
  if (prompt_append && typeof merged.prompt === "string") {
    merged.prompt = merged.prompt + "\n" + resolvePromptAppend(prompt_append);
  }
  return merged;
}
