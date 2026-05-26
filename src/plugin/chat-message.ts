import type { WittyDiagnosisAgentConfig } from "../config"
import type { PluginContext } from "./types"

import { hasConnectedProvidersCache } from "../shared"
import { getAgentConfigKey } from "../shared/agent-display-names"
import { normalizeSDKResponse } from "../shared/normalize-sdk-response"
import {
  clearPinnedSessionModel,
  getPinnedSessionModel,
  getSessionModel,
  setPinnedSessionModel,
  setSessionModel,
} from "../shared/session-model-state"
import {
  getMainSessionID,
  getSessionAgent,
  updateSessionAgent,
} from "../features/claude-code-session-state"
import { applyUltraworkModelOverrideOnMessage } from "./ultrawork-model-override"
import { parseRalphLoopArguments } from "../hooks/ralph-loop/command-arguments"
import {
  extractPromptTextFromParts,
  getInheritanceTargetAgentKey,
  isModelInheritanceUserPrompt,
} from "../shared/model-inheritance-prompt"
import { parseSessionModelField } from "../shared/session-model-parse"

import type { CreatedHooks } from "../create-hooks"

type SessionModel = { providerID: string; modelID: string }

type FirstMessageVariantGate = {
  shouldOverride: (sessionID: string) => boolean
  markApplied: (sessionID: string) => void
}

type ChatMessagePart = { type: string; text?: string; [key: string]: unknown }
export type ChatMessageHandlerOutput = { message: Record<string, unknown>; parts: ChatMessagePart[] }
export type ChatMessageInput = {
  sessionID: string
  agent?: string
  model?: { providerID: string; modelID: string }
}
type StartWorkHookOutput = { parts: Array<{ type: string; text?: string }> }

function isModelInheritingAgentSwitch(previousAgent?: string, incomingAgent?: string): boolean {
  if (!previousAgent || !incomingAgent) return false
  const prev = getAgentConfigKey(previousAgent)
  const next = getAgentConfigKey(incomingAgent)
  if (prev === next) return false

  const sourceAgents = new Set(["fuxi", "dayu", "baize", "kuafu", "xuanyuan"])
  const targetAgents = new Set(["dayu", "baize", "xuanyuan"])
  return sourceAgents.has(prev) && targetAgents.has(next)
}

function isSameModel(a?: SessionModel, b?: SessionModel): boolean {
  if (!a || !b) return false
  return a.providerID === b.providerID && a.modelID === b.modelID
}

type SessionGetCtx = PluginContext & {
  client?: {
    session?: {
      get?: (req: { path: { id: string }; query?: { directory?: string } }) => Promise<unknown>
    }
  }
  directory?: string
}

async function tryResolveSessionModelFromOpenCode(
  ctx: PluginContext,
  sessionID: string
): Promise<SessionModel | undefined> {
  const c = ctx as SessionGetCtx
  const get = c.client?.session?.get
  if (!get) {
    return undefined
  }
  try {
    const res = await get({
      path: { id: sessionID },
      ...(typeof c.directory === "string" && c.directory.length > 0
        ? { query: { directory: c.directory } }
        : {}),
    })
    const data = normalizeSDKResponse(
      res,
      null as { model?: unknown } | null,
      { preferResponseOnMissingData: true }
    )
    const record = data && typeof data === "object" ? (data as Record<string, unknown>) : null
    let parsed = parseSessionModelField(record?.model)
    if (!parsed && record) {
      const p = record.providerID
      const m = record.modelID
      if (typeof p === "string" && typeof m === "string") {
        parsed = { providerID: p, modelID: m }
      }
    }
    return parsed
  } catch {
    return undefined
  }
}

async function resolveInheritanceModel(args: {
  ctx: PluginContext
  sessionID: string
  mem: SessionModel | undefined
  inputModel: SessionModel | undefined
  /**
   * OpenCode may run `/start-dayu` in a *child* session; `session.get(child)` can miss the user’s
   * model while the main session still has it — pass main id here when applicable.
   */
  liveFetchSessionID?: string
  /**
   * `/witty-diag`, `/start-dayu`, `/start-baize`: always keep the plugin session map (`mem`) when it
   * conflicts with `input.model` — the message often carries the target agent default, not the user’s
   * prior `/models` choice.
   */
  modelInheritanceSlash?: boolean
}): Promise<SessionModel | undefined> {
  const { ctx, sessionID, mem, inputModel, liveFetchSessionID, modelInheritanceSlash } = args
  const live = await tryResolveSessionModelFromOpenCode(ctx, liveFetchSessionID ?? sessionID)

  let effective: SessionModel | undefined = mem

  if (!effective && inputModel) {
    effective = inputModel
  }
  if (!effective && live) {
    effective = live
  }

  if (!mem && live && inputModel && !isSameModel(live, inputModel)) {
    effective = live
  } else if (effective && inputModel && !isSameModel(effective, inputModel)) {
    if (modelInheritanceSlash && mem && !isSameModel(mem, inputModel)) {
      effective = mem
    } else {
      effective = inputModel
    }
  }

  // After /models, the plugin map and `input.model` can both still show the previous model while
  // `session.get` already reflects the new selection — prefer live when it disagrees with stale
  // effective and input is missing or still aligned with that stale value.
  if (
    live &&
    effective &&
    !isSameModel(live, effective) &&
    (!inputModel || isSameModel(inputModel, effective))
  ) {
    effective = live
  }

  return effective
}

function isStartWorkHookOutput(value: unknown): value is StartWorkHookOutput {
  if (typeof value !== "object" || value === null) return false
  const record = value as Record<string, unknown>
  const partsValue = record["parts"]
  if (!Array.isArray(partsValue)) return false
  return partsValue.every((part) => {
    if (typeof part !== "object" || part === null) return false
    const partRecord = part as Record<string, unknown>
    return typeof partRecord["type"] === "string"
  })
}

export function createChatMessageHandler(args: {
  ctx: PluginContext
  pluginConfig: WittyDiagnosisAgentConfig
  firstMessageVariantGate: FirstMessageVariantGate
  hooks: CreatedHooks
}): (
  input: ChatMessageInput,
  output: ChatMessageHandlerOutput
) => Promise<void> {
  const { ctx, pluginConfig, firstMessageVariantGate, hooks } = args
  const pluginContext = ctx as {
    client: {
      tui: {
        showToast: (input: {
          body: {
            title: string
            message: string
            variant: "warning"
            duration: number
          }
        }) => Promise<unknown>
      }
    }
  }
  const isRuntimeFallbackEnabled =
    hooks.runtimeFallback !== null &&
    hooks.runtimeFallback !== undefined &&
    (typeof pluginConfig.runtime_fallback === "boolean"
      ? pluginConfig.runtime_fallback
      : (pluginConfig.runtime_fallback?.enabled ?? false))

  return async (
    input: ChatMessageInput,
    output: ChatMessageHandlerOutput
  ): Promise<void> => {
    const promptText = extractPromptTextFromParts(output.parts)
    const shouldInheritForSlashCommand = isModelInheritanceUserPrompt(promptText)
    const inheritanceTargetKey =
      shouldInheritForSlashCommand
        ? getInheritanceTargetAgentKey(promptText) ?? input.agent
        : undefined

    const mainSessionID = getMainSessionID()
    const isChildOfMainSession =
      Boolean(mainSessionID && input.sessionID && input.sessionID !== mainSessionID)

    let previousAgent = getSessionAgent(input.sessionID)
    let mem = getSessionModel(input.sessionID)
    if (isChildOfMainSession && mainSessionID) {
      if (previousAgent === undefined) {
        const fromMain = getSessionAgent(mainSessionID)
        if (fromMain !== undefined) {
          previousAgent = fromMain
        }
      }
      if (mem === undefined) {
        const fromMain = getSessionModel(mainSessionID)
        if (fromMain !== undefined) {
          mem = fromMain
        }
      }
    }

    const liveFetchSessionID =
      isChildOfMainSession && mainSessionID ? mainSessionID : input.sessionID

    /**
     * `getSessionAgent` is only set after prior turns; on first user message or cold session it is
     * empty while `input.agent` already shows the UI agent (e.g. Fuxi). Inheritance must still see
     * Fuxi→Xuanyuan for `/witty-diag`.
     */
    const previousAgentForInheritance = previousAgent ?? input.agent

    if (
      !shouldInheritForSlashCommand &&
      previousAgent &&
      input.agent &&
      getAgentConfigKey(previousAgent) === getAgentConfigKey(input.agent) &&
      mem &&
      input.model &&
      !isSameModel(mem, input.model)
    ) {
      setSessionModel(input.sessionID, input.model)
      mem = getSessionModel(input.sessionID)
    }

    if (
      shouldInheritForSlashCommand &&
      inheritanceTargetKey &&
      isModelInheritingAgentSwitch(previousAgentForInheritance, inheritanceTargetKey)
    ) {
      const resolved = await resolveInheritanceModel({
        ctx,
        sessionID: input.sessionID,
        mem,
        inputModel: input.model,
        liveFetchSessionID,
        modelInheritanceSlash: true,
      })
      if (resolved) {
        setPinnedSessionModel(input.sessionID, resolved)
      }
    }

    if (input.agent) {
      updateSessionAgent(input.sessionID, input.agent)
    }

    let pinnedModel = getPinnedSessionModel(input.sessionID)
    const isSwitchingForInheritance =
      shouldInheritForSlashCommand &&
      Boolean(inheritanceTargetKey) &&
      isModelInheritingAgentSwitch(previousAgentForInheritance, inheritanceTargetKey)

    if (
      pinnedModel &&
      input.model &&
      !isSwitchingForInheritance &&
      !isSameModel(pinnedModel, input.model)
    ) {
      clearPinnedSessionModel(input.sessionID)
      pinnedModel = undefined
    }

    if (pinnedModel) {
      output.message["model"] = {
        providerID: pinnedModel.providerID,
        modelID: pinnedModel.modelID,
      }
    }

    if (firstMessageVariantGate.shouldOverride(input.sessionID)) {
      firstMessageVariantGate.markApplied(input.sessionID)
    }

    if (!isRuntimeFallbackEnabled) {
      await hooks.modelFallback?.["chat.message"]?.(input, output)
    }
    const modelOverride = output.message["model"]
    if (
      modelOverride &&
      typeof modelOverride === "object" &&
      "providerID" in modelOverride &&
      "modelID" in modelOverride
    ) {
      const providerID = (modelOverride as { providerID?: string }).providerID
      const modelID = (modelOverride as { modelID?: string }).modelID
      if (typeof providerID === "string" && typeof modelID === "string") {
        setSessionModel(input.sessionID, { providerID, modelID })
      }
    } else if (pinnedModel) {
      setSessionModel(input.sessionID, pinnedModel)
    } else if (input.model) {
      setSessionModel(input.sessionID, input.model)
    }
    await hooks.stopContinuationGuard?.["chat.message"]?.(input)
    await hooks.backgroundNotificationHook?.["chat.message"]?.(input, output)
    await hooks.runtimeFallback?.["chat.message"]?.(input, output)
    await hooks.keywordDetector?.["chat.message"]?.(input, output)
    await hooks.thinkMode?.["chat.message"]?.(input, output)
    await hooks.claudeCodeHooks?.["chat.message"]?.(input, output)
    await hooks.autoSlashCommand?.["chat.message"]?.(input, output)

    const finalModel = output.message["model"]
    if (
      finalModel &&
      typeof finalModel === "object" &&
      "providerID" in finalModel &&
      "modelID" in finalModel
    ) {
      const fp = (finalModel as { providerID?: string }).providerID
      const fm = (finalModel as { modelID?: string }).modelID
      if (typeof fp === "string" && typeof fm === "string") {
        setSessionModel(input.sessionID, { providerID: fp, modelID: fm })
      }
    }

    if (hooks.startWork && isStartWorkHookOutput(output)) {
      await hooks.startWork["chat.message"]?.(input, output)
    }

    if (!hasConnectedProvidersCache()) {
      pluginContext.client.tui
        .showToast({
          body: {
            title: "⚠️ Provider Cache Missing",
            message:
              "Model filtering disabled. RESTART OpenCode to enable full functionality.",
            variant: "warning" as const,
            duration: 6000,
          },
        })
        .catch(() => {})
    }

    if (hooks.ralphLoop) {
      const parts = output.parts
      const promptTextRalph =
        parts
          ?.filter((p) => p.type === "text" && p.text)
          .map((p) => p.text)
          .join("\n")
          .trim() || ""

      const isRalphLoopTemplate =
        promptTextRalph.includes("You are starting a Ralph Loop") &&
        promptTextRalph.includes("<user-task>")
      const isCancelRalphTemplate = promptTextRalph.includes(
        "Cancel the currently active Ralph Loop",
      )

      if (isRalphLoopTemplate) {
        const taskMatch = promptTextRalph.match(/<user-task>\s*([\s\S]*?)\s*<\/user-task>/i)
        const rawTask = taskMatch?.[1]?.trim() || ""
        const parsedArguments = parseRalphLoopArguments(rawTask)

        hooks.ralphLoop.startLoop(input.sessionID, parsedArguments.prompt, {
          maxIterations: parsedArguments.maxIterations,
          completionPromise: parsedArguments.completionPromise,
          strategy: parsedArguments.strategy,
        })
      } else if (isCancelRalphTemplate) {
        hooks.ralphLoop.cancelLoop(input.sessionID)
      }
    }

    applyUltraworkModelOverrideOnMessage(pluginConfig, input.agent, output, pluginContext.client.tui, input.sessionID)
  }
}
