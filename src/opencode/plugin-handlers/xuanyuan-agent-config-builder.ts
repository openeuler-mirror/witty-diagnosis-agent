import { XUANYUAN_PERMISSION, getXuanyuanPrompt } from "../agents/xuanyuan";
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

type XuanyuanOverride = Record<string, unknown> & {
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

export async function buildXuanyuanAgentConfig(params: {
  configAgentPlan: Record<string, unknown> | undefined;
  pluginXuanyuanOverride: XuanyuanOverride | undefined;
  userCategories: Record<string, CategoryConfig> | undefined;
  currentModel: string | undefined;
  outputLanguage: "zh" | "en";
}): Promise<Record<string, unknown>> {
  const categoryConfig = params.pluginXuanyuanOverride?.category
    ? resolveCategoryConfig(params.pluginXuanyuanOverride.category, params.userCategories)
    : undefined;

  const requirement = AGENT_MODEL_REQUIREMENTS["xuanyuan"];
  const connectedProviders = readConnectedProvidersCache();
  const availableModels = await fetchAvailableModels(undefined, {
    connectedProviders: connectedProviders ?? undefined,
  });

  const modelResolution = resolveModelPipeline({
    intent: {
      uiSelectedModel: params.currentModel,
      userModel: params.pluginXuanyuanOverride?.model ?? categoryConfig?.model,
    },
    constraints: { availableModels },
    policy: {
      fallbackChain: requirement?.fallbackChain,
      systemDefaultModel: undefined,
    },
  });

  const resolvedModel = modelResolution?.model;
  const resolvedVariant = modelResolution?.variant;

  const variantToUse = params.pluginXuanyuanOverride?.variant ?? resolvedVariant;
  const reasoningEffortToUse =
    params.pluginXuanyuanOverride?.reasoningEffort ?? categoryConfig?.reasoningEffort;
  const textVerbosityToUse =
    params.pluginXuanyuanOverride?.textVerbosity ?? categoryConfig?.textVerbosity;
  const thinkingToUse = params.pluginXuanyuanOverride?.thinking ?? categoryConfig?.thinking;
  const temperatureToUse =
    params.pluginXuanyuanOverride?.temperature ?? categoryConfig?.temperature;
  const topPToUse = params.pluginXuanyuanOverride?.top_p ?? categoryConfig?.top_p;
  const maxTokensToUse =
    params.pluginXuanyuanOverride?.maxTokens ?? categoryConfig?.maxTokens;

  const base: Record<string, unknown> = {
    ...(resolvedModel ? { model: resolvedModel } : {}),
    ...(variantToUse ? { variant: variantToUse } : {}),
    mode: "all",
    prompt: await getXuanyuanPrompt(resolvedModel, params.outputLanguage),
    permission: XUANYUAN_PERMISSION,
    description: `${(params.configAgentPlan?.description as string) ?? l(AGENT_LOCALIZATION["xuanyuan"].description, params.outputLanguage)}`,
    color: (params.configAgentPlan?.color as string) ?? "#2196F3",
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

  const override = params.pluginXuanyuanOverride;
  if (!override) return base;

  const { prompt_append, ...restOverride } = override;
  const merged = { ...base, ...restOverride };
  if (prompt_append && typeof merged.prompt === "string") {
    merged.prompt = merged.prompt + "\n" + resolvePromptAppend(prompt_append);
  }
  return merged;
}
