/// <reference types="bun-types" />

import { describe, test, expect, beforeEach, afterEach, spyOn } from "bun:test"
import { createBuiltinAgents } from "./builtin-agents"
import type { AgentConfig } from "@opencode-ai/sdk"
import { clearSkillCache } from "../features/opencode-skill-loader/skill-content"
import * as connectedProvidersCache from "../shared/connected-providers-cache"
import * as modelAvailability from "../shared/model-availability"
import * as shared from "../shared"

const TEST_DEFAULT_MODEL = "anthropic/claude-opus-4-6"

describe("createBuiltinAgents with model overrides", () => {
  test("Sisyphus with default model has thinking config when all models available", async () => {
    // #given
    const fetchSpy = spyOn(shared, "fetchAvailableModels").mockResolvedValue(
      new Set([
        "anthropic/claude-opus-4-6",
        "kimi-for-coding/k2p5",
        "opencode/kimi-k2.5-free",
        "zai-coding-plan/glm-5",
        "opencode/big-pickle",
      ])
    )

    try {
      // #when
      const agents = await createBuiltinAgents([], {}, undefined, TEST_DEFAULT_MODEL, undefined, undefined, [], {})

      // #then
      expect(agents.sisyphus.model).toBe("anthropic/claude-opus-4-6")
      expect(agents.sisyphus.thinking).toEqual({ type: "enabled", budgetTokens: 32000 })
      expect(agents.sisyphus.reasoningEffort).toBeUndefined()
    } finally {
      fetchSpy.mockRestore()
    }
  })

  test("Sisyphus with GPT model override has reasoningEffort, no thinking", async () => {
    // #given
    const overrides = {
      sisyphus: { model: "github-copilot/gpt-5.2" },
    }

    // #when
    const agents = await createBuiltinAgents([], overrides, undefined, TEST_DEFAULT_MODEL, undefined, undefined, [], undefined, undefined)

    // #then
    expect(agents.sisyphus.model).toBe("github-copilot/gpt-5.2")
    expect(agents.sisyphus.reasoningEffort).toBe("medium")
    expect(agents.sisyphus.thinking).toBeUndefined()
  })

  test("user config model takes priority over uiSelectedModel for sisyphus", async () => {
    // #given
    const fetchSpy = spyOn(shared, "fetchAvailableModels").mockResolvedValue(
      new Set(["openai/gpt-5.2", "anthropic/claude-sonnet-4-6"])
    )
    const uiSelectedModel = "openai/gpt-5.2"
    const overrides = {
      sisyphus: { model: "google/antigravity-claude-opus-4-5-thinking" },
    }

    try {
      // #when
      const agents = await createBuiltinAgents(
        [],
        overrides,
        undefined,
        TEST_DEFAULT_MODEL,
        undefined,
        undefined,
        [],
        undefined,
        undefined,
        uiSelectedModel
      )

      // #then
      expect(agents.sisyphus).toBeDefined()
      expect(agents.sisyphus.model).toBe("google/antigravity-claude-opus-4-5-thinking")
    } finally {
      fetchSpy.mockRestore()
    }
  })

  test("Sisyphus is created on first run when no availableModels or cache exist", async () => {
    // #given
    const systemDefaultModel = "anthropic/claude-opus-4-6"
    const cacheSpy = spyOn(connectedProvidersCache, "readConnectedProvidersCache").mockReturnValue(null)
    const fetchSpy = spyOn(shared, "fetchAvailableModels").mockResolvedValue(new Set())

    try {
      // #when
      const agents = await createBuiltinAgents([], {}, undefined, systemDefaultModel, undefined, undefined, [], {})

      // #then
      expect(agents.sisyphus).toBeDefined()
      expect(agents.sisyphus.model).toBe("anthropic/claude-opus-4-6")
    } finally {
      cacheSpy.mockRestore()
      fetchSpy.mockRestore()
    }
  })

   test("non-model overrides are still applied after factory rebuild", async () => {
     // #given
     const overrides = {
       sisyphus: { model: "github-copilot/gpt-5.2", temperature: 0.5 },
     }

     // #when
     const agents = await createBuiltinAgents([], overrides, undefined, TEST_DEFAULT_MODEL, undefined, undefined, [], undefined, undefined)

     // #then
     expect(agents.sisyphus.model).toBe("github-copilot/gpt-5.2")
     expect(agents.sisyphus.temperature).toBe(0.5)
   })

  test("createBuiltinAgents excludes disabled skills from availableSkills", async () => {
    // #given
    const disabledSkills = new Set(["playwright"])

    // #when
    const agents = await createBuiltinAgents([], {}, undefined, TEST_DEFAULT_MODEL, undefined, undefined, [], undefined, undefined, undefined, disabledSkills)

    // #then
    expect(agents.sisyphus.prompt).not.toContain("playwright")
    expect(agents.sisyphus.prompt).toContain("frontend-ui-ux")
    expect(agents.sisyphus.prompt).toContain("git-master")
  })
})

describe("createBuiltinAgents without systemDefaultModel", () => {
  test("sisyphus created via connected cache fallback when all providers available", async () => {
    // #given
    const cacheSpy = spyOn(connectedProvidersCache, "readConnectedProvidersCache").mockReturnValue([
      "anthropic", "kimi-for-coding", "opencode", "zai-coding-plan"
    ])
    const fetchSpy = spyOn(shared, "fetchAvailableModels").mockResolvedValue(
      new Set([
        "anthropic/claude-opus-4-6",
        "kimi-for-coding/k2p5",
        "opencode/kimi-k2.5-free",
        "zai-coding-plan/glm-5",
        "opencode/big-pickle",
      ])
    )

    try {
      // #when
      const agents = await createBuiltinAgents([], {}, undefined, undefined, undefined, undefined, [], {})

      // #then
      expect(agents.sisyphus).toBeDefined()
      expect(agents.sisyphus.model).toBe("anthropic/claude-opus-4-6")
    } finally {
      cacheSpy.mockRestore()
      fetchSpy.mockRestore()
    }
  })
})

describe("createBuiltinAgents with requiresAnyModel gating (sisyphus)", () => {
  test("sisyphus is created when at least one fallback model is available", async () => {
    // #given
    const fetchSpy = spyOn(shared, "fetchAvailableModels").mockResolvedValue(
      new Set(["anthropic/claude-opus-4-6"])
    )

    try {
      // #when
      const agents = await createBuiltinAgents([], {}, undefined, TEST_DEFAULT_MODEL, undefined, undefined, [], {})

      // #then
      expect(agents.sisyphus).toBeDefined()
    } finally {
      fetchSpy.mockRestore()
    }
  })

  test("sisyphus is created on first run when no availableModels or cache exist", async () => {
    // #given
    const cacheSpy = spyOn(connectedProvidersCache, "readConnectedProvidersCache").mockReturnValue(null)
    const fetchSpy = spyOn(shared, "fetchAvailableModels").mockResolvedValue(new Set())

    try {
      // #when
      const agents = await createBuiltinAgents([], {}, undefined, TEST_DEFAULT_MODEL, undefined, undefined, [], {})

      // #then
      expect(agents.sisyphus).toBeDefined()
      expect(agents.sisyphus.model).toBe("anthropic/claude-opus-4-6")
    } finally {
      cacheSpy.mockRestore()
      fetchSpy.mockRestore()
    }
  })

  test("sisyphus is created when explicit config provided even if no models available", async () => {
    // #given
    const fetchSpy = spyOn(shared, "fetchAvailableModels").mockResolvedValue(new Set())
    const overrides = {
      sisyphus: { model: "anthropic/claude-opus-4-6" },
    }

    try {
      // #when
      const agents = await createBuiltinAgents([], overrides, undefined, TEST_DEFAULT_MODEL, undefined, undefined, [], {})

      // #then
      expect(agents.sisyphus).toBeDefined()
    } finally {
      fetchSpy.mockRestore()
    }
  })

  test("sisyphus is not created when no fallback model is available and provider not connected", async () => {
    // #given - only openai/gpt-5.2 available, not in sisyphus fallback chain
    const fetchSpy = spyOn(shared, "fetchAvailableModels").mockResolvedValue(
      new Set(["openai/gpt-5.2"])
    )
    const cacheSpy = spyOn(connectedProvidersCache, "readConnectedProvidersCache").mockReturnValue([])

    try {
      // #when
      const agents = await createBuiltinAgents([], {}, undefined, TEST_DEFAULT_MODEL, undefined, undefined, [], {})

      // #then
      expect(agents.sisyphus).toBeUndefined()
    } finally {
      fetchSpy.mockRestore()
      cacheSpy.mockRestore()
    }
  })
})

describe("buildAgent with category and skills", () => {
  const { buildAgent } = require("./agent-builder")
  const TEST_MODEL = "anthropic/claude-opus-4-6"

  beforeEach(() => {
    clearSkillCache()
  })

  afterEach(() => {
    clearSkillCache()
  })

  test("agent with category inherits category settings", () => {
    // #given - agent factory that sets category but no model
    const source = {
      "test-agent": () =>
        ({
          description: "Test agent",
          category: "visual-engineering",
        }) as AgentConfig,
    }

    // #when
    const agent = buildAgent(source["test-agent"], TEST_MODEL)

    // #then - category's built-in model is applied
    expect(agent.model).toBe("google/gemini-3.1-pro")
  })

  test("agent with category and existing model keeps existing model", () => {
    // #given
    const source = {
      "test-agent": () =>
        ({
          description: "Test agent",
          category: "visual-engineering",
          model: "custom/model",
        }) as AgentConfig,
    }

    // #when
    const agent = buildAgent(source["test-agent"], TEST_MODEL)

    // #then - explicit model takes precedence over category
    expect(agent.model).toBe("custom/model")
  })

  test("agent with category inherits variant", () => {
    // #given
    const source = {
      "test-agent": () =>
        ({
          description: "Test agent",
          category: "custom-category",
        }) as AgentConfig,
    }

    const categories = {
      "custom-category": {
        model: "openai/gpt-5.2",
        variant: "xhigh",
      },
    }

    // #when
    const agent = buildAgent(source["test-agent"], TEST_MODEL, categories)

    // #then
    expect(agent.model).toBe("openai/gpt-5.2")
    expect(agent.variant).toBe("xhigh")
  })

  test("agent with skills has content prepended to prompt", () => {
    // #given
    const source = {
      "test-agent": () =>
        ({
          description: "Test agent",
          skills: ["frontend-ui-ux"],
          prompt: "Original prompt content",
        }) as AgentConfig,
    }

    // #when
    const agent = buildAgent(source["test-agent"], TEST_MODEL)

    // #then
    expect(agent.prompt).toContain("Role: Designer-Turned-Developer")
    expect(agent.prompt).toContain("Original prompt content")
    expect(agent.prompt).toMatch(/Designer-Turned-Developer[\s\S]*Original prompt content/s)
  })

  test("agent without category or skills works as before", () => {
    // #given
    const source = {
      "test-agent": () =>
        ({
          description: "Test agent",
          model: "custom/model",
          temperature: 0.5,
          prompt: "Base prompt",
        }) as AgentConfig,
    }

    // #when
    const agent = buildAgent(source["test-agent"], TEST_MODEL)

    // #then
    expect(agent.model).toBe("custom/model")
    expect(agent.temperature).toBe(0.5)
    expect(agent.prompt).toBe("Base prompt")
  })
})

describe("override.category expansion in createBuiltinAgents", () => {
  test("sisyphus override with category expands category properties", async () => {
    // #given
    const overrides = {
      sisyphus: { category: "ultrabrain" } as any,
    }

    // #when
    const agents = await createBuiltinAgents([], overrides, undefined, TEST_DEFAULT_MODEL)

    // #then - ultrabrain category: model=openai/gpt-5.3-codex, variant=xhigh
    expect(agents.sisyphus).toBeDefined()
    expect(agents.sisyphus.model).toBe("openai/gpt-5.3-codex")
    expect(agents.sisyphus.variant).toBe("xhigh")
  })
})

describe("Deadlock prevention - fetchAvailableModels must not receive client", () => {
   test("createBuiltinAgents should call fetchAvailableModels with undefined client to prevent deadlock", async () => {
     // #given - This test ensures we don't regress on issue #1301
     const fetchSpy = spyOn(modelAvailability, "fetchAvailableModels").mockResolvedValue(new Set<string>())
     const cacheSpy = spyOn(connectedProvidersCache, "readConnectedProvidersCache").mockReturnValue(null)

     const mockClient = {
       provider: { list: () => Promise.resolve({ data: { connected: [] } }) },
       model: { list: () => Promise.resolve({ data: [] }) },
     }

     // #when
     await createBuiltinAgents(
       [],
       {},
       undefined,
       TEST_DEFAULT_MODEL,
       undefined,
       undefined,
       [],
       mockClient
     )

     // #then
     expect(fetchSpy).toHaveBeenCalled()
     const firstCallArgs = fetchSpy.mock.calls[0]
     expect(firstCallArgs[0]).toBeUndefined()

     fetchSpy.mockRestore?.()
     cacheSpy.mockRestore?.()
   })
})
