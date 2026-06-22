export type FallbackEntry = {
  providers: string[]
  model: string
  variant?: string // Entry-specific variant (e.g., GPT→high, Opus→max)
}

export type ModelRequirement = {
  fallbackChain: FallbackEntry[]
  variant?: string // Default variant (used when entry doesn't specify one)
  requiresAnyModel?: boolean // If true, requires at least ONE model in fallbackChain to be available (or empty availability treated as unavailable)
  requiresProvider?: string[] // If set, only activates when any of these providers is connected
}

export const AGENT_MODEL_REQUIREMENTS: Record<string, ModelRequirement> = {
  baize: {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-r1", variant: "medium" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5", variant: "medium" },
      { providers: ["opencode"], model: "minimax-m2.5-free", variant: "medium" },
    ],
    requiresProvider: ["opencode", "zai-coding-plan"],
  },
  "multimodal-looker": {
    fallbackChain: [
      { providers: ["zai-coding-plan"], model: "glm-4.6v" },
      { providers: ["opencode"], model: "deepseek-v3" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
  xuanyuan: {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-r1", variant: "max" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5", variant: "high" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
  fuxi: {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-r1", variant: "max" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5", variant: "high" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
  nuwa: {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-r1", variant: "max" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5", variant: "high" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
  "nuwa-sub": {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-r1", variant: "max" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5", variant: "high" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
  dayu: {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-r1", variant: "max" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5", variant: "high" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
  kuafu: {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-v3", variant: "medium" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
  "taiyi": {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-v3", variant: "medium" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
}

export const CATEGORY_MODEL_REQUIREMENTS: Record<string, ModelRequirement> = {
  "visual-engineering": {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-v3", variant: "high" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5" },
      { providers: ["opencode"], model: "minimax-m2.5-free", variant: "max" },
    ],
  },
  ultrabrain: {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-r1", variant: "xhigh" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5", variant: "high" },
      { providers: ["opencode"], model: "minimax-m2.5-free", variant: "max" },
    ],
  },
  deep: {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-r1", variant: "medium" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5", variant: "max" },
      { providers: ["opencode"], model: "minimax-m2.5-free", variant: "high" },
    ],
  },
  artistry: {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-v3", variant: "high" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5", variant: "max" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
  quick: {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-v3" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
  "unspecified-low": {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-v3" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5", variant: "medium" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
  "unspecified-high": {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-r1", variant: "max" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5", variant: "high" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
  writing: {
    fallbackChain: [
      { providers: ["opencode"], model: "deepseek-v3" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
}
