import { describe, test, expect, spyOn } from "bun:test"

import { createAutoSlashCommandHook } from "../hooks/auto-slash-command"
import { createChatMessageHandler } from "./chat-message"
import * as sessionState from "../features/claude-code-session-state"
import {
  clearPinnedSessionModel,
  clearSessionModel,
  setSessionModel,
  setPinnedSessionModel,
} from "../shared/session-model-state"

type ChatMessagePart = { type: string; text?: string; [key: string]: unknown }
type ChatMessageHandlerOutput = { message: Record<string, unknown>; parts: ChatMessagePart[] }

function createMockHandlerArgs(overrides?: {
  pluginConfig?: Record<string, unknown>
  shouldOverride?: boolean
  autoSlashCommand?: unknown
}) {
  const appliedSessions: string[] = []
  return {
    ctx: { client: { tui: { showToast: async () => {} } } } as any,
    pluginConfig: (overrides?.pluginConfig ?? {}) as any,
    firstMessageVariantGate: {
      shouldOverride: () => overrides?.shouldOverride ?? false,
      markApplied: (sessionID: string) => { appliedSessions.push(sessionID) },
    },
    hooks: {
      stopContinuationGuard: null,
      backgroundNotificationHook: null,
      keywordDetector: null,
      claudeCodeHooks: null,
      autoSlashCommand: overrides?.autoSlashCommand ?? null,
      startWork: null,
      ralphLoop: null,
    } as any,
    _appliedSessions: appliedSessions,
  }
}

function createMockInput(agent?: string, model?: { providerID: string; modelID: string }) {
  return {
    sessionID: "test-session",
    agent,
    model,
  }
}

function createMockOutput(variant?: string): ChatMessageHandlerOutput {
  const message: Record<string, unknown> = {}
  if (variant !== undefined) {
    message["variant"] = variant
  }
  return { message, parts: [{ type: "text", text: "normal message" }] }
}

describe("createChatMessageHandler - TUI variant passthrough", () => {
  test("first message: does not override TUI variant when user has no selection", async () => {
    //#given - first message, no user-selected variant
    const args = createMockHandlerArgs({ shouldOverride: true })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("hephaestus", { providerID: "openai", modelID: "gpt-5.3-codex" })
    const output = createMockOutput() // no variant set

    //#when
    await handler(input, output)

    //#then - TUI sent undefined, should stay undefined (no config override)
    expect(output.message["variant"]).toBeUndefined()
  })

  test("first message: preserves user-selected variant when already set", async () => {
    //#given - first message, user already selected "xhigh" variant in OpenCode UI
    const args = createMockHandlerArgs({ shouldOverride: true })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("hephaestus", { providerID: "openai", modelID: "gpt-5.3-codex" })
    const output = createMockOutput("xhigh") // user selected xhigh

    //#when
    await handler(input, output)

    //#then - user's xhigh must be preserved
    expect(output.message["variant"]).toBe("xhigh")
  })

  test("subsequent message: preserves TUI variant", async () => {
    //#given - not first message, variant already set
    const args = createMockHandlerArgs({ shouldOverride: false })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("hephaestus", { providerID: "openai", modelID: "gpt-5.3-codex" })
    const output = createMockOutput("xhigh")

    //#when
    await handler(input, output)

    //#then
    expect(output.message["variant"]).toBe("xhigh")
  })

  test("subsequent message: does not inject variant when TUI sends none", async () => {
    //#given - not first message, no variant from TUI
    const args = createMockHandlerArgs({ shouldOverride: false })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("hephaestus", { providerID: "openai", modelID: "gpt-5.3-codex" })
    const output = createMockOutput() // no variant

    //#when
    await handler(input, output)

    //#then - should stay undefined, not auto-resolved from config
    expect(output.message["variant"]).toBeUndefined()
  })

  test("first message: marks gate as applied regardless of variant presence", async () => {
    //#given - first message with user-selected variant
    const args = createMockHandlerArgs({ shouldOverride: true })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("hephaestus", { providerID: "openai", modelID: "gpt-5.3-codex" })
    const output = createMockOutput("xhigh")

    //#when
    await handler(input, output)

    //#then - gate should still be marked as applied
    expect(args._appliedSessions).toContain("test-session")
  })

  test("injects queued background notifications through chat.message hook", async () => {
    //#given
    const args = createMockHandlerArgs()
    args.hooks.backgroundNotificationHook = {
      "chat.message": async (
        _input: { sessionID: string },
        output: ChatMessageHandlerOutput,
      ): Promise<void> => {
        output.parts.push({
          type: "text",
          text: "<system-reminder>[BACKGROUND TASK COMPLETED]</system-reminder>",
        })
      },
    }
    const handler = createChatMessageHandler(args)
    const input = createMockInput("hephaestus", { providerID: "openai", modelID: "gpt-5.3-codex" })
    const output = createMockOutput()

    //#when
    await handler(input, output)

    //#then
    expect(output.parts.some((p) => String(p.text).includes("[BACKGROUND TASK COMPLETED]"))).toBe(true)
  })

  test("updates session agent on every message when input.agent exists", async () => {
    //#given
    const updateSpy = spyOn(sessionState, "updateSessionAgent")
    const args = createMockHandlerArgs({ shouldOverride: false })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("dayu", { providerID: "openai", modelID: "gpt-5.3-codex" })
    const output = createMockOutput()

    //#when
    await handler(input, output)

    //#then
    expect(updateSpy).toHaveBeenCalledWith("test-session", "dayu")
  })

  test("applies pinned session model when present", async () => {
    //#given
    setPinnedSessionModel("test-session", {
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })
    const args = createMockHandlerArgs({ shouldOverride: false })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("dayu", { providerID: "deepseek", modelID: "deepseek-chat" })
    const output = createMockOutput()

    //#when
    await handler(input, output)

    //#then
    expect(output.message["model"]).toEqual({
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })

    clearPinnedSessionModel("test-session")
  })

  test("/start-dayu: inherits session map when message model differs (ignore host attachment)", async () => {
    //#given
    sessionState.updateSessionAgent("test-session", "Xuanyuan")
    setSessionModel("test-session", {
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })
    const args = createMockHandlerArgs({ shouldOverride: false })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("Dayu", { providerID: "anthropic", modelID: "claude-sonnet-4-6" })
    const output = createMockOutput()
    output.parts[0].text = "/start-dayu keep model"

    //#when
    await handler(input, output)

    //#then
    expect(output.message["model"]).toEqual({
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })

    clearPinnedSessionModel("test-session")
    clearSessionModel("test-session")
  })

  test("/start-dayu: inherits map when display names differ from message model", async () => {
    //#given
    sessionState.updateSessionAgent("test-session", "Xuanyuan (Controller)")
    setSessionModel("test-session", {
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })
    const args = createMockHandlerArgs({ shouldOverride: false })
    const handler = createChatMessageHandler(args)
    const input = createMockInput(
      "Dayu (Orchestration and Scheduling)",
      { providerID: "opencode", modelID: "minimax-m2.5-free" }
    )
    const output = createMockOutput()
    output.parts[0].text = "/start-dayu keep model"

    //#when
    await handler(input, output)

    //#then
    expect(output.message["model"]).toEqual({
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })

    clearPinnedSessionModel("test-session")
    clearSessionModel("test-session")
  })

  test("clears pinned model when user manually changes model without agent switch", async () => {
    //#given
    setPinnedSessionModel("test-session", {
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })
    const args = createMockHandlerArgs({ shouldOverride: false })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("Dayu (Orchestration and Scheduling)", {
      providerID: "opencode",
      modelID: "minimax-m2.5-free",
    })
    const output = createMockOutput()

    //#when
    await handler(input, output)

    //#then
    expect(output.message["model"]).toBeUndefined()

    clearPinnedSessionModel("test-session")
    clearSessionModel("test-session")
  })

  test("does not inherit model on plain agent switch without slash command", async () => {
    //#given
    sessionState.updateSessionAgent("test-session", "Xuanyuan (Controller)")
    setSessionModel("test-session", {
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })
    const args = createMockHandlerArgs({ shouldOverride: false })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("Dayu (Orchestration and Scheduling)", {
      providerID: "opencode",
      modelID: "minimax-m2.5-free",
    })
    const output = createMockOutput()
    output.parts[0].text = "hello"

    //#when
    await handler(input, output)

    //#then
    expect(output.message["model"]).toBeUndefined()

    clearPinnedSessionModel("test-session")
    clearSessionModel("test-session")
  })

  test("expanded /start-dayu instruction inherits session map over message model", async () => {
    //#given
    sessionState.updateSessionAgent("test-session", "Xuanyuan (Controller)")
    setSessionModel("test-session", {
      providerID: "myprovider",
      modelID: "ep-20260212143927-jsbht",
    })
    const args = createMockHandlerArgs({ shouldOverride: false })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("Dayu (Orchestration and Scheduling)", {
      providerID: "opencode",
      modelID: "minimax-m2.5-free",
    })
    const output = createMockOutput()
    output.parts[0].text =
      "<command-instruction>\nYou are switching this session to the Dayu agent.\n</command-instruction>"

    //#when
    await handler(input, output)

    //#then
    expect(output.message["model"]).toEqual({
      providerID: "myprovider",
      modelID: "ep-20260212143927-jsbht",
    })

    clearPinnedSessionModel("test-session")
    clearSessionModel("test-session")
  })

  test("/start-dayu: inherits model when input.agent still Fuxi (host lag)", async () => {
    const sessionGet = async () => ({
      data: {
        model: { providerID: "anthropic", modelID: "claude-sonnet-4-6" },
      },
    })
    const args = createMockHandlerArgs()
    args.ctx = {
      client: {
        tui: { showToast: async () => {} },
        session: { get: sessionGet },
      },
    } as any
    sessionState.updateSessionAgent("test-session", "Fuxi (Diagnostic Planner)")
    const handler = createChatMessageHandler(args)
    const input = createMockInput("Fuxi (Diagnostic Planner)", {
      providerID: "openai",
      modelID: "gpt-4.1",
    })
    const output = createMockOutput()
    output.parts[0].text = "/start-dayu run diagnostics"

    await handler(input, output)

    expect(output.message["model"]).toEqual({
      providerID: "anthropic",
      modelID: "claude-sonnet-4-6",
    })

    clearPinnedSessionModel("test-session")
    clearSessionModel("test-session")
  })

  test("/start-dayu: keeps map when input.model is target default but map has prior /models choice (same agent)", async () => {
    const sessionGet = async () => ({
      data: {
        model: { providerID: "zhipu", modelID: "glm-4-7" },
      },
    })
    const args = createMockHandlerArgs()
    args.ctx = {
      client: {
        tui: { showToast: async () => {} },
        session: { get: sessionGet },
      },
    } as any
    sessionState.updateSessionAgent("test-session", "Fuxi (Diagnostic Planner)")
    setSessionModel("test-session", {
      providerID: "zhipu",
      modelID: "glm-4-7",
    })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("Fuxi (Diagnostic Planner)", {
      providerID: "minimax",
      modelID: "minimax-m2.5-free",
    })
    const output = createMockOutput()
    output.parts[0].text = "/start-dayu"

    await handler(input, output)

    expect(output.message["model"]).toEqual({
      providerID: "zhipu",
      modelID: "glm-4-7",
    })

    clearPinnedSessionModel("test-session")
    clearSessionModel("test-session")
  })

  test("/start-dayu: child session inherits agent + model from main session (OpenCode subsession handoff)", async () => {
    const parentId = "ses_parent_main"
    const childId = "ses_child_dayu"
    sessionState.setMainSession(parentId)
    sessionState.updateSessionAgent(parentId, "Fuxi (Diagnostic Planner)")
    setSessionModel(parentId, {
      providerID: "myprovider",
      modelID: "ep-20260212143927-jsbht",
    })
    const sessionGet = async (req: { path: { id: string } }) => {
      if (req.path.id === parentId) {
        return {
          data: {
            model: { providerID: "myprovider", modelID: "ep-20260212143927-jsbht" },
          },
        }
      }
      return { data: {} }
    }
    const args = createMockHandlerArgs()
    args.ctx = {
      client: {
        tui: { showToast: async () => {} },
        session: { get: sessionGet },
      },
    } as any
    const handler = createChatMessageHandler(args)
    const input = {
      ...createMockInput("Dayu (Orchestration and Scheduling)", {
        providerID: "opencode",
        modelID: "minimax-m2.5-free",
      }),
      sessionID: childId,
    }
    const output = createMockOutput()
    output.parts[0].text =
      "<command-instruction>\nYou are switching this session to the Dayu agent.\n</command-instruction>"

    await handler(input, output)

    expect(output.message["model"]).toEqual({
      providerID: "myprovider",
      modelID: "ep-20260212143927-jsbht",
    })

    sessionState.setMainSession(undefined)
    clearPinnedSessionModel(childId)
    clearSessionModel(parentId)
    clearSessionModel(childId)
  })

  test("/start-dayu: prefers session.get when map + input.model still show pre-/models model", async () => {
    const sessionGet = async () => ({
      data: {
        model: { providerID: "anthropic", modelID: "claude-sonnet-4-6" },
      },
    })
    const args = createMockHandlerArgs()
    args.ctx = {
      client: {
        tui: { showToast: async () => {} },
        session: { get: sessionGet },
      },
    } as any
    sessionState.updateSessionAgent("test-session", "Fuxi (Diagnostic Planner)")
    setSessionModel("test-session", {
      providerID: "openai",
      modelID: "gpt-4.1",
    })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("Fuxi (Diagnostic Planner)", {
      providerID: "openai",
      modelID: "gpt-4.1",
    })
    const output = createMockOutput()
    output.parts[0].text = "/start-dayu next step"

    await handler(input, output)

    expect(output.message["model"]).toEqual({
      providerID: "anthropic",
      modelID: "claude-sonnet-4-6",
    })

    clearPinnedSessionModel("test-session")
    clearSessionModel("test-session")
  })

  test("/witty-diag: Fuxi map (deepseek) wins over Xuanyuan default on expanded message", async () => {
    sessionState.updateSessionAgent("test-session", "Fuxi (Diagnostic Planner)")
    setSessionModel("test-session", {
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })
    const args = createMockHandlerArgs()
    args.ctx = {
      client: {
        tui: { showToast: async () => {} },
        session: { get: async () => ({ data: {} }) },
      },
    } as any
    const handler = createChatMessageHandler(args)
    const input = createMockInput("Xuanyuan (Controller)", {
      providerID: "opencode",
      modelID: "minimax-m2.5-free",
    })
    const output = createMockOutput()
    output.parts[0].text =
      "<command-instruction>\nYou are switching this session to the Xuanyuan agent.\n\n## Purpose\n"
    await handler(input, output)

    expect(output.message["model"]).toEqual({
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })

    clearPinnedSessionModel("test-session")
    clearSessionModel("test-session")
    sessionState.clearSessionAgent("test-session")
  })

  test("/witty-diag: inherits when getSessionAgent was never set but input.agent is Fuxi", async () => {
    sessionState.clearSessionAgent("test-session")
    clearSessionModel("test-session")
    clearPinnedSessionModel("test-session")
    const sessionGet = async () => ({
      data: {
        model: { providerID: "deepseek", modelID: "deepseek-chat" },
      },
    })
    const args = createMockHandlerArgs()
    args.ctx = {
      client: {
        tui: { showToast: async () => {} },
        session: { get: sessionGet },
      },
    } as any
    const handler = createChatMessageHandler(args)
    const input = createMockInput("Fuxi (Diagnostic Planner)", {
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })
    const output = createMockOutput()
    output.parts[0].text = "/witty-diag run"

    await handler(input, output)

    expect(output.message["model"]).toEqual({
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })

    clearPinnedSessionModel("test-session")
    clearSessionModel("test-session")
    sessionState.clearSessionAgent("test-session")
  })

  test("cold start: prefers session.get when hook input lags (empty map)", async () => {
    const sessionGet = async () => ({
      data: {
        model: { providerID: "anthropic", modelID: "claude-sonnet-4-6" },
      },
    })
    const args = createMockHandlerArgs()
    args.ctx = {
      client: {
        tui: { showToast: async () => {} },
        session: { get: sessionGet },
      },
    } as any
    sessionState.updateSessionAgent("test-session", "Fuxi (Diagnostic Planner)")
    const handler = createChatMessageHandler(args)
    const input = createMockInput("Xuanyuan (Controller)", {
      providerID: "openai",
      modelID: "gpt-4.1",
    })
    const output = createMockOutput()
    output.parts[0].text = "/witty-diag test"

    await handler(input, output)

    expect(output.message["model"]).toEqual({
      providerID: "anthropic",
      modelID: "claude-sonnet-4-6",
    })

    clearPinnedSessionModel("test-session")
    clearSessionModel("test-session")
  })

  test("clears pinned model on normal agent switch with manual model change", async () => {
    //#given
    sessionState.updateSessionAgent("test-session", "Dayu (Orchestration and Scheduling)")
    setPinnedSessionModel("test-session", {
      providerID: "myprovider",
      modelID: "ep-20260212143927-jsbht",
    })
    const args = createMockHandlerArgs({ shouldOverride: false })
    const handler = createChatMessageHandler(args)
    const input = createMockInput("Xuanyuan (Controller)", {
      providerID: "deepseek",
      modelID: "deepseek-chat",
    })
    const output = createMockOutput()
    output.parts[0].text = "hello"

    //#when
    await handler(input, output)

    //#then
    expect(output.message["model"]).toBeUndefined()

    clearPinnedSessionModel("test-session")
    clearSessionModel("test-session")
  })

  describe("/start-dayu 切换（chat.message + auto-slash）", () => {
    test("Fuxi → Dayu：展开模板、updateSessionAgent(dayu)、沿用 deepseek 模型", async () => {
      const updateSpy = spyOn(sessionState, "updateSessionAgent")
      const sessionGet = async () => ({
        data: { model: { providerID: "deepseek", modelID: "deepseek-chat" } },
      })
      const args = createMockHandlerArgs({
        autoSlashCommand: createAutoSlashCommandHook(),
      })
      args.ctx = {
        client: {
          tui: { showToast: async () => {} },
          session: { get: sessionGet },
        },
      } as any

      sessionState.updateSessionAgent("test-session", "Fuxi (Diagnostic Planner)")
      clearPinnedSessionModel("test-session")
      clearSessionModel("test-session")

      const handler = createChatMessageHandler(args)
      const input = createMockInput("Fuxi (Diagnostic Planner)", {
        providerID: "deepseek",
        modelID: "deepseek-chat",
      })
      const output = createMockOutput()
      output.parts[0].text = "/start-dayu run orchestration"

      await handler(input, output)

      expect(updateSpy).toHaveBeenCalledWith("test-session", "dayu")
      expect(output.parts[0].text).toContain("You are switching this session to the Dayu agent")
      expect(output.message["model"]).toEqual({
        providerID: "deepseek",
        modelID: "deepseek-chat",
      })

      updateSpy.mockRestore()
      clearPinnedSessionModel("test-session")
      clearSessionModel("test-session")
    })
  })
})
