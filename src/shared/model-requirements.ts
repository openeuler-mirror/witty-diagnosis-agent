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
      { providers: ["anthropic", "github-copilot", "opencode"], model: "claude-opus-4-6", variant: "max" },
      { providers: ["openai", "github-copilot", "opencode"], model: "gpt-5.2", variant: "high" },
      { providers: ["opencode"], model: "kimi-k2.5-free" },
      { providers: ["google", "github-copilot", "opencode"], model: "gemini-3.1-pro" },
    ],
  },
  "multimodal-looker": {
    fallbackChain: [
      { providers: ["opencode"], model: "kimi-k2.5-free" },
      { providers: ["google", "github-copilot", "opencode"], model: "gemini-3-flash" },
      { providers: ["openai", "github-copilot", "opencode"], model: "gpt-5.2" },
      { providers: ["zai-coding-plan"], model: "glm-4.6v" },
      { providers: ["openai", "github-copilot", "opencode"], model: "gpt-5-nano" },
    ],
  },
  fuxi: {
    fallbackChain: [
      { providers: ["anthropic", "github-copilot", "opencode"], model: "claude-opus-4-6", variant: "max" },
      { providers: ["openai", "github-copilot", "opencode"], model: "gpt-5.2", variant: "high" },
      { providers: ["opencode"], model: "kimi-k2.5-free" },
      { providers: ["google", "github-copilot", "opencode"], model: "gemini-3.1-pro" },
    ],
  },
  dayu: {
    fallbackChain: [
      { providers: ["anthropic", "github-copilot", "opencode"], model: "claude-opus-4-6", variant: "max" },
      { providers: ["openai", "github-copilot", "opencode"], model: "gpt-5.2", variant: "high" },
      { providers: ["opencode"], model: "kimi-k2.5-free" },
      { providers: ["google", "github-copilot", "opencode"], model: "gemini-3.1-pro" },
    ],
  },
  kuafu: {
    fallbackChain: [
      { providers: ["openai", "github-copilot", "opencode"], model: "gpt-5.2", variant: "medium" },
      { providers: ["anthropic", "github-copilot", "opencode"], model: "claude-sonnet-4-6" },
      { providers: ["google", "github-copilot", "opencode"], model: "gemini-3-flash" },
      { providers: ["opencode"], model: "minimax-m2.5-free" },
    ],
  },
}

export const CATEGORY_MODEL_REQUIREMENTS: Record<string, ModelRequirement> = {
  "visual-engineering": {
    fallbackChain: [
      { providers: ["google", "github-copilot", "opencode"], model: "gemini-3.1-pro", variant: "high" },
      { providers: ["zai-coding-plan", "opencode"], model: "glm-5" },
      { providers: ["anthropic", "github-copilot", "opencode"], model: "claude-opus-4-6", variant: "max" },
    ],
  },
  ultrabrain: {
    fallbackChain: [
      { providers: ["openai", "opencode"], model: "gpt-4o", variant: "xhigh" },
      { providers: ["google", "github-copilot", "opencode"], model: "gemini-3.1-pro", variant: "high" },
      { providers: ["anthropic", "github-copilot", "opencode"], model: "claude-opus-4-6", variant: "max" },
    ],
  },
  deep: {
    fallbackChain: [
      { providers: ["openai", "opencode"], model: "gpt-4o", variant: "medium" },
      { providers: ["anthropic", "github-copilot", "opencode"], model: "claude-opus-4-6", variant: "max" },
      { providers: ["google", "github-copilot", "opencode"], model: "gemini-3.1-pro", variant: "high" },
    ],
  },
  artistry: {
    fallbackChain: [
      { providers: ["google", "github-copilot", "opencode"], model: "gemini-3.1-pro", variant: "high" },
      { providers: ["anthropic", "github-copilot", "opencode"], model: "claude-opus-4-6", variant: "max" },
      { providers: ["openai", "github-copilot", "opencode"], model: "gpt-5.2" },
    ],
  },
  quick: {
    fallbackChain: [
      { providers: ["anthropic", "github-copilot", "opencode"], model: "claude-haiku-4-5" },
      { providers: ["google", "github-copilot", "opencode"], model: "gemini-3-flash" },
      { providers: ["opencode"], model: "gpt-5-nano" },
    ],
  },
  "unspecified-low": {
    fallbackChain: [
      { providers: ["anthropic", "github-copilot", "opencode"], model: "claude-sonnet-4-6" },
      { providers: ["openai", "opencode"], model: "gpt-4o", variant: "medium" },
      { providers: ["google", "github-copilot", "opencode"], model: "gemini-3-flash" },
    ],
  },
  "unspecified-high": {
    fallbackChain: [
      { providers: ["anthropic", "github-copilot", "opencode"], model: "claude-opus-4-6", variant: "max" },
      { providers: ["openai", "github-copilot", "opencode"], model: "gpt-5.2", variant: "high" },
      { providers: ["google", "github-copilot", "opencode"], model: "gemini-3.1-pro" },
    ],
  },
  writing: {
    fallbackChain: [
      { providers: ["opencode"], model: "kimi-k2.5-free" },
      { providers: ["google", "github-copilot", "opencode"], model: "gemini-3-flash" },
      { providers: ["anthropic", "github-copilot", "opencode"], model: "claude-sonnet-4-6" },
    ],
  },
}
