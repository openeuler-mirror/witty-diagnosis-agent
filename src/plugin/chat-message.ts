import type { WittyDiagnosisAgentConfig } from "../config"
import type { PluginContext } from "./types"

import { hasConnectedProvidersCache } from "../shared"
import { getAgentConfigKey } from "../shared/agent-display-names"
import {
  clearPinnedSessionModel,
  getPinnedSessionModel,
  getSessionModel,
  setPinnedSessionModel,
  setSessionModel,
} from "../shared/session-model-state"
import { getSessionAgent, updateSessionAgent } from "../features/claude-code-session-state"
import { applyUltraworkModelOverrideOnMessage } from "./ultrawork-model-override"
import { parseRalphLoopArguments } from "../hooks/ralph-loop/command-arguments"

import type { CreatedHooks } from "../create-hooks"

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

function isSameModel(
  a?: { providerID: string; modelID: string },
  b?: { providerID: string; modelID: string }
): boolean {
  if (!a || !b) return false
  return a.providerID === b.providerID && a.modelID === b.modelID
}

function extractPromptText(parts: ChatMessagePart[]): string {
  return parts
    .filter((p) => p.type === "text")
    .map((p) => p.text || "")
    .join(" ")
    .trim()
}

function isModelInheritanceSlashCommand(promptText: string): boolean {
  return /^\/(start-dayu|start-baize|witty-diag)\b/i.test(promptText)
}

function isModelInheritanceCommandTemplate(promptText: string): boolean {
  return /you are switching this session to the (dayu|baize|xuanyuan) agent\./i.test(promptText)
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
    const promptText = extractPromptText(output.parts)
    const shouldInheritForSlashCommand =
      isModelInheritanceSlashCommand(promptText) || isModelInheritanceCommandTemplate(promptText)
    const previousAgent = getSessionAgent(input.sessionID)
    const previousModel = getSessionModel(input.sessionID)
    if (
      shouldInheritForSlashCommand &&
      isModelInheritingAgentSwitch(previousAgent, input.agent) &&
      previousModel
    ) {
      setPinnedSessionModel(input.sessionID, previousModel)
    }

    if (input.agent) {
      updateSessionAgent(input.sessionID, input.agent)
    }

    let pinnedModel = getPinnedSessionModel(input.sessionID)
    const isSwitchingForInheritance =
      shouldInheritForSlashCommand && isModelInheritingAgentSwitch(previousAgent, input.agent)

    // If user manually changed model (e.g. /models) outside inheritance commands, release pin.
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
      const promptText =
        parts
          ?.filter((p) => p.type === "text" && p.text)
          .map((p) => p.text)
          .join("\n")
          .trim() || ""

      const isRalphLoopTemplate =
        promptText.includes("You are starting a Ralph Loop") &&
        promptText.includes("<user-task>")
      const isCancelRalphTemplate = promptText.includes(
        "Cancel the currently active Ralph Loop",
      )

      if (isRalphLoopTemplate) {
        const taskMatch = promptText.match(/<user-task>\s*([\s\S]*?)\s*<\/user-task>/i)
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
