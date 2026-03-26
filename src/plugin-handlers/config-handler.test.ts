/// <reference types="bun-types" />

import { describe, test, expect, spyOn, beforeEach, afterEach } from "bun:test"
import { resolveCategoryConfig, createConfigHandler } from "./config-handler"
import type { CategoryConfig } from "../config/schema"
import type { WittyDiagnosisAgentConfig } from "../config"
import { getAgentDisplayName } from "../shared/agent-display-names"

import * as agents from "../agents"
import * as commandLoader from "../features/claude-code-command-loader"
import * as builtinCommands from "../features/builtin-commands"
import * as skillLoader from "../features/opencode-skill-loader"
import * as agentLoader from "../features/claude-code-agent-loader"
import * as mcpLoader from "../features/claude-code-mcp-loader"
import * as pluginLoader from "../features/claude-code-plugin-loader"
import * as mcpModule from "../mcp"
import * as shared from "../shared"
import * as configDir from "../shared/opencode-config-dir"
import * as permissionCompat from "../shared/permission-compat"
import * as modelResolver from "../shared/model-resolver"

beforeEach(() => {
  spyOn(agents, "createBuiltinAgents" as any).mockResolvedValue({
    sisyphus: { name: "sisyphus", prompt: "test", mode: "primary" },
    oracle: { name: "oracle", prompt: "test", mode: "subagent" },
  })

  spyOn(commandLoader, "loadUserCommands" as any).mockResolvedValue({})
  spyOn(commandLoader, "loadProjectCommands" as any).mockResolvedValue({})
  spyOn(commandLoader, "loadOpencodeGlobalCommands" as any).mockResolvedValue({})
  spyOn(commandLoader, "loadOpencodeProjectCommands" as any).mockResolvedValue({})

  spyOn(builtinCommands, "loadBuiltinCommands" as any).mockReturnValue({})

  spyOn(skillLoader, "loadUserSkills" as any).mockResolvedValue({})
  spyOn(skillLoader, "loadProjectSkills" as any).mockResolvedValue({})
  spyOn(skillLoader, "loadOpencodeGlobalSkills" as any).mockResolvedValue({})
  spyOn(skillLoader, "loadOpencodeProjectSkills" as any).mockResolvedValue({})
  spyOn(skillLoader, "discoverUserClaudeSkills" as any).mockResolvedValue([])
  spyOn(skillLoader, "discoverProjectClaudeSkills" as any).mockResolvedValue([])
  spyOn(skillLoader, "discoverOpencodeGlobalSkills" as any).mockResolvedValue([])
  spyOn(skillLoader, "discoverOpencodeProjectSkills" as any).mockResolvedValue([])

  spyOn(agentLoader, "loadUserAgents" as any).mockReturnValue({})
  spyOn(agentLoader, "loadProjectAgents" as any).mockReturnValue({})

  spyOn(mcpLoader, "loadMcpConfigs" as any).mockResolvedValue({ servers: {} })

  spyOn(pluginLoader, "loadAllPluginComponents" as any).mockResolvedValue({
    commands: {},
    skills: {},
    agents: {},
    mcpServers: {},
    hooksConfigs: [],
    plugins: [],
    errors: [],
  })

  spyOn(mcpModule, "createBuiltinMcps" as any).mockReturnValue({})

  spyOn(shared, "log" as any).mockImplementation(() => {})
  spyOn(shared, "fetchAvailableModels" as any).mockResolvedValue(new Set(["anthropic/claude-opus-4-6"]))
  spyOn(shared, "readConnectedProvidersCache" as any).mockReturnValue(null)

  spyOn(configDir, "getOpenCodeConfigPaths" as any).mockReturnValue({
    global: "/tmp/.config/opencode",
    project: "/tmp/.opencode",
  })

  spyOn(permissionCompat, "migrateAgentConfig" as any).mockImplementation((config: Record<string, unknown>) => config)

  spyOn(modelResolver, "resolveModelWithFallback" as any).mockReturnValue({ model: "anthropic/claude-opus-4-6" })
})

afterEach(() => {
  (agents.createBuiltinAgents as any)?.mockRestore?.()
  ;(commandLoader.loadUserCommands as any)?.mockRestore?.()
  ;(commandLoader.loadProjectCommands as any)?.mockRestore?.()
  ;(commandLoader.loadOpencodeGlobalCommands as any)?.mockRestore?.()
  ;(commandLoader.loadOpencodeProjectCommands as any)?.mockRestore?.()
  ;(builtinCommands.loadBuiltinCommands as any)?.mockRestore?.()
  ;(skillLoader.loadUserSkills as any)?.mockRestore?.()
  ;(skillLoader.loadProjectSkills as any)?.mockRestore?.()
  ;(skillLoader.loadOpencodeGlobalSkills as any)?.mockRestore?.()
  ;(skillLoader.loadOpencodeProjectSkills as any)?.mockRestore?.()
  ;(skillLoader.discoverUserClaudeSkills as any)?.mockRestore?.()
  ;(skillLoader.discoverProjectClaudeSkills as any)?.mockRestore?.()
  ;(skillLoader.discoverOpencodeGlobalSkills as any)?.mockRestore?.()
  ;(skillLoader.discoverOpencodeProjectSkills as any)?.mockRestore?.()
  ;(agentLoader.loadUserAgents as any)?.mockRestore?.()
  ;(agentLoader.loadProjectAgents as any)?.mockRestore?.()
  ;(mcpLoader.loadMcpConfigs as any)?.mockRestore?.()
  ;(pluginLoader.loadAllPluginComponents as any)?.mockRestore?.()
  ;(mcpModule.createBuiltinMcps as any)?.mockRestore?.()
  ;(shared.log as any)?.mockRestore?.()
  ;(shared.fetchAvailableModels as any)?.mockRestore?.()
  ;(shared.readConnectedProvidersCache as any)?.mockRestore?.()
  ;(configDir.getOpenCodeConfigPaths as any)?.mockRestore?.()
  ;(permissionCompat.migrateAgentConfig as any)?.mockRestore?.()
  ;(modelResolver.resolveModelWithFallback as any)?.mockRestore?.()
})

describe("resolveCategoryConfig", () => {
  test("resolves ultrabrain category config", () => {
    // given
    const categoryName = "ultrabrain"

    // when
    const config = resolveCategoryConfig(categoryName)

    // then
    expect(config).toBeDefined()
    expect(config?.model).toBe("openai/gpt-5.3-codex")
    expect(config?.variant).toBe("xhigh")
  })

  test("resolves visual-engineering category config", () => {
    // given
    const categoryName = "visual-engineering"

    // when
    const config = resolveCategoryConfig(categoryName)

    // then
    expect(config).toBeDefined()
    expect(config?.model).toBe("google/gemini-3.1-pro")
  })

  test("user categories override default categories", () => {
    // given
    const categoryName = "ultrabrain"
    const userCategories: Record<string, CategoryConfig> = {
      ultrabrain: {
        model: "google/antigravity-claude-opus-4-5-thinking",
        temperature: 0.1,
      },
    }

    // when
    const config = resolveCategoryConfig(categoryName, userCategories)

    // then
    expect(config).toBeDefined()
    expect(config?.model).toBe("google/antigravity-claude-opus-4-5-thinking")
    expect(config?.temperature).toBe(0.1)
  })

  test("returns undefined for unknown category", () => {
    // given
    const categoryName = "nonexistent-category"

    // when
    const config = resolveCategoryConfig(categoryName)

    // then
    expect(config).toBeUndefined()
  })

  test("falls back to default when user category has no entry", () => {
    // given
    const categoryName = "ultrabrain"
    const userCategories: Record<string, CategoryConfig> = {
      "visual-engineering": {
        model: "custom/visual-model",
      },
    }

    // when
    const config = resolveCategoryConfig(categoryName, userCategories)

    // then - falls back to DEFAULT_CATEGORIES
    expect(config).toBeDefined()
    expect(config?.model).toBe("openai/gpt-5.3-codex")
    expect(config?.variant).toBe("xhigh")
  })

  test("preserves all category properties (temperature, top_p, tools, etc.)", () => {
    // given
    const categoryName = "custom-category"
    const userCategories: Record<string, CategoryConfig> = {
      "custom-category": {
        model: "test/model",
        temperature: 0.5,
        top_p: 0.9,
        maxTokens: 32000,
        tools: { tool1: true, tool2: false },
      },
    }

    // when
    const config = resolveCategoryConfig(categoryName, userCategories)

    // then
    expect(config).toBeDefined()
    expect(config?.model).toBe("test/model")
    expect(config?.temperature).toBe(0.5)
    expect(config?.top_p).toBe(0.9)
    expect(config?.maxTokens).toBe(32000)
    expect(config?.tools).toEqual({ tool1: true, tool2: false })
  })
})

describe("default_agent behavior with Sisyphus orchestration", () => {
  test("sets default_agent to fuxi when missing", async () => {
    // #given
    const pluginConfig: WittyDiagnosisAgentConfig = {}
    const config: Record<string, unknown> = {
      model: "anthropic/claude-opus-4-6",
      agent: {},
    }
    const handler = createConfigHandler({
      ctx: { directory: "/tmp" },
      pluginConfig,
      modelCacheState: {
        anthropicContext1MEnabled: false,
        modelContextLimitsCache: new Map(),
      },
    })

    // #when
    await handler(config)

    // #then
    expect(config.default_agent).toBe(getAgentDisplayName("fuxi"))
  })

  test("sets default_agent to fuxi when configured default_agent is empty after trim", async () => {
    // given
    const pluginConfig: WittyDiagnosisAgentConfig = {}
    const config: Record<string, unknown> = {
      model: "anthropic/claude-opus-4-6",
      default_agent: "    ",
      agent: {},
    }
    const handler = createConfigHandler({
      ctx: { directory: "/tmp" },
      pluginConfig,
      modelCacheState: {
        anthropicContext1MEnabled: false,
        modelContextLimitsCache: new Map(),
      },
    })

    // when
    await handler(config)

    // then
    expect(config.default_agent).toBe(getAgentDisplayName("fuxi"))
  })

  test("preserves custom default_agent names while trimming whitespace", async () => {
    // given
    const pluginConfig: WittyDiagnosisAgentConfig = {}
    const config: Record<string, unknown> = {
      model: "anthropic/claude-opus-4-6",
      default_agent: "  Custom Agent  ",
      agent: {},
    }
    const handler = createConfigHandler({
      ctx: { directory: "/tmp" },
      pluginConfig,
      modelCacheState: {
        anthropicContext1MEnabled: false,
        modelContextLimitsCache: new Map(),
      },
    })

    // when
    await handler(config)

    // then
    expect(config.default_agent).toBe("Custom Agent")
  })
})

describe("Deadlock prevention - fetchAvailableModels must not receive client", () => {
  test("fetchAvailableModels should be called with undefined client to prevent deadlock during plugin init", async () => {
    // given - This test ensures we don't regress on issue #1301
    // Passing client to fetchAvailableModels during config handler causes deadlock:
    // - Plugin init waits for server response (client.provider.list())
    // - Server waits for plugin init to complete before handling requests
    const fetchSpy = spyOn(shared, "fetchAvailableModels" as any).mockResolvedValue(new Set<string>())

    const pluginConfig: WittyDiagnosisAgentConfig = {
      sisyphus_agent: {
        planner_enabled: true,
      },
    }
    const config: Record<string, unknown> = {
      model: "anthropic/claude-opus-4-6",
      agent: {},
    }
    const mockClient = {
      provider: { list: () => Promise.resolve({ data: { connected: [] } }) },
      model: { list: () => Promise.resolve({ data: [] }) },
    }
    const handler = createConfigHandler({
      ctx: { directory: "/tmp", client: mockClient },
      pluginConfig,
      modelCacheState: {
        anthropicContext1MEnabled: false,
        modelContextLimitsCache: new Map(),
      },
    })

    // when
    await handler(config)

    // then - fetchAvailableModels must be called with undefined as first argument (no client)
    // This prevents the deadlock described in issue #1301
    expect(fetchSpy).toHaveBeenCalled()
    const firstCallArgs = fetchSpy.mock.calls[0]
    expect(firstCallArgs[0]).toBeUndefined()

    fetchSpy.mockRestore?.()
  })
})

describe("config-handler plugin loading error boundary (#1559)", () => {
  test("returns empty defaults when loadAllPluginComponents throws", async () => {
    //#given
    ;(pluginLoader.loadAllPluginComponents as any).mockRestore?.()
    spyOn(pluginLoader, "loadAllPluginComponents" as any).mockRejectedValue(new Error("crash"))
    const pluginConfig: WittyDiagnosisAgentConfig = {}
    const config: Record<string, unknown> = {
      model: "anthropic/claude-opus-4-6",
      agent: {},
    }
    const handler = createConfigHandler({
      ctx: { directory: "/tmp" },
      pluginConfig,
      modelCacheState: {
        anthropicContext1MEnabled: false,
        modelContextLimitsCache: new Map(),
      },
    })

    //#when
    await handler(config)

    //#then
    expect(config.agent).toBeDefined()
  })

  test("returns empty defaults when loadAllPluginComponents times out", async () => {
    //#given
    ;(pluginLoader.loadAllPluginComponents as any).mockRestore?.()
    spyOn(pluginLoader, "loadAllPluginComponents" as any).mockImplementation(
      () => new Promise(() => {})
    )
    const pluginConfig: WittyDiagnosisAgentConfig = {
      experimental: { plugin_load_timeout_ms: 100 },
    }
    const config: Record<string, unknown> = {
      model: "anthropic/claude-opus-4-6",
      agent: {},
    }
    const handler = createConfigHandler({
      ctx: { directory: "/tmp" },
      pluginConfig,
      modelCacheState: {
        anthropicContext1MEnabled: false,
        modelContextLimitsCache: new Map(),
      },
    })

    //#when
    await handler(config)

    //#then
    expect(config.agent).toBeDefined()
  }, 5000)

  test("logs error when loadAllPluginComponents fails", async () => {
    //#given
    ;(pluginLoader.loadAllPluginComponents as any).mockRestore?.()
    spyOn(pluginLoader, "loadAllPluginComponents" as any).mockRejectedValue(new Error("crash"))
    const logSpy = shared.log as ReturnType<typeof spyOn>
    const pluginConfig: WittyDiagnosisAgentConfig = {}
    const config: Record<string, unknown> = {
      model: "anthropic/claude-opus-4-6",
      agent: {},
    }
    const handler = createConfigHandler({
      ctx: { directory: "/tmp" },
      pluginConfig,
      modelCacheState: {
        anthropicContext1MEnabled: false,
        modelContextLimitsCache: new Map(),
      },
    })

    //#when
    await handler(config)

    //#then
    const logCalls = logSpy.mock.calls.map((c: unknown[]) => c[0])
    const hasPluginFailureLog = logCalls.some(
      (msg: string) => typeof msg === "string" && msg.includes("Plugin loading failed")
    )
    expect(hasPluginFailureLog).toBe(true)
  })

  test("passes through plugin data on successful load (identity test)", async () => {
    //#given
    ;(pluginLoader.loadAllPluginComponents as any).mockRestore?.()
    spyOn(pluginLoader, "loadAllPluginComponents" as any).mockResolvedValue({
      commands: { "test-cmd": { description: "test", template: "test" } },
      skills: {},
      agents: {},
      mcpServers: {},
      hooksConfigs: [],
      plugins: [{ name: "test-plugin", version: "1.0.0" }],
      errors: [],
    })
    const pluginConfig: WittyDiagnosisAgentConfig = {}
    const config: Record<string, unknown> = {
      model: "anthropic/claude-opus-4-6",
      agent: {},
    }
    const handler = createConfigHandler({
      ctx: { directory: "/tmp" },
      pluginConfig,
      modelCacheState: {
        anthropicContext1MEnabled: false,
        modelContextLimitsCache: new Map(),
      },
    })

    //#when
    await handler(config)

    //#then
    const commands = config.command as Record<string, unknown>
    expect(commands["test-cmd"]).toBeDefined()
  })
})

describe("disable_wda_env pass-through", () => {
  test("passes disable_wda_env=true to createBuiltinAgents", async () => {
    //#given
    const createBuiltinAgentsMock = agents.createBuiltinAgents as unknown as {
      mockResolvedValue: (value: Record<string, unknown>) => void
      mock: { calls: unknown[][] }
    }
    createBuiltinAgentsMock.mockResolvedValue({
      sisyphus: { name: "sisyphus", prompt: "without-env", mode: "primary" },
    })

    const pluginConfig: WittyDiagnosisAgentConfig = {
      experimental: { disable_wda_env: true },
    }
    const config: Record<string, unknown> = {
      model: "anthropic/claude-opus-4-6",
      agent: {},
    }
    const handler = createConfigHandler({
      ctx: { directory: "/tmp" },
      pluginConfig,
      modelCacheState: {
        anthropicContext1MEnabled: false,
        modelContextLimitsCache: new Map(),
      },
    })

    //#when
    await handler(config)

    //#then
    const lastCall =
      createBuiltinAgentsMock.mock.calls[createBuiltinAgentsMock.mock.calls.length - 1]
    expect(lastCall).toBeDefined()
    expect(lastCall?.[12]).toBe(true)
  })

  test("passes disable_wda_env=false to createBuiltinAgents when omitted", async () => {
    //#given
    const createBuiltinAgentsMock = agents.createBuiltinAgents as unknown as {
      mockResolvedValue: (value: Record<string, unknown>) => void
      mock: { calls: unknown[][] }
    }
    createBuiltinAgentsMock.mockResolvedValue({
      sisyphus: { name: "sisyphus", prompt: "with-env", mode: "primary" },
    })

    const pluginConfig: WittyDiagnosisAgentConfig = {}
    const config: Record<string, unknown> = {
      model: "anthropic/claude-opus-4-6",
      agent: {},
    }
    const handler = createConfigHandler({
      ctx: { directory: "/tmp" },
      pluginConfig,
      modelCacheState: {
        anthropicContext1MEnabled: false,
        modelContextLimitsCache: new Map(),
      },
    })

    //#when
    await handler(config)

    //#then
    const lastCall =
      createBuiltinAgentsMock.mock.calls[createBuiltinAgentsMock.mock.calls.length - 1]
    expect(lastCall).toBeDefined()
    expect(lastCall?.[12]).toBe(false)
  })
})
