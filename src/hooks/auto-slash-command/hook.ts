import {
  detectSlashCommand,
  extractPromptText,
  findSlashCommandPartIndex,
} from "./detector"
import { executeSlashCommand, type ExecutorOptions } from "./executor"
import { getPinnedSessionModel, setPinnedSessionModel } from "../../shared/session-model-state"
import {
  AUTO_SLASH_COMMAND_TAG_CLOSE,
  AUTO_SLASH_COMMAND_TAG_OPEN,
} from "./constants"
import {
  getSessionAgent,
  updateSessionAgent,
} from "../../features/claude-code-session-state"
import type {
  AutoSlashCommandHookInput,
  AutoSlashCommandHookOutput,
  CommandExecuteBeforeInput,
  CommandExecuteBeforeOutput,
} from "./types"
import type { LoadedSkill } from "../../features/opencode-skill-loader"

const sessionProcessedCommands = new Set<string>()
const sessionProcessedCommandExecutions = new Set<string>()
const WITTY_DIAG_ALLOWED_SOURCE_AGENTS = new Set(["fuxi", "dayu", "baize", "kuafu"])

function canSwitchToXuanyuan(inputAgent?: string): boolean {
  if (!inputAgent) return false
  return WITTY_DIAG_ALLOWED_SOURCE_AGENTS.has(inputAgent.toLowerCase())
}

function shouldPreserveModelForCommand(command: string): boolean {
  return command === "start-dayu" || command === "start-baize" || command === "witty-diag"
}

export interface AutoSlashCommandHookOptions {
  skills?: LoadedSkill[]
}

export function createAutoSlashCommandHook(options?: AutoSlashCommandHookOptions) {
  const executorOptions: ExecutorOptions = {
    skills: options?.skills,
  }

  return {
    "chat.message": async (
      input: AutoSlashCommandHookInput,
      output: AutoSlashCommandHookOutput
    ): Promise<void> => {
      const promptText = extractPromptText(output.parts)

      if (
        promptText.includes(AUTO_SLASH_COMMAND_TAG_OPEN) ||
        promptText.includes(AUTO_SLASH_COMMAND_TAG_CLOSE)
      ) {
        return
      }

      const parsed = detectSlashCommand(promptText)

      if (!parsed) {
        return
      }

      const commandKey = `${input.sessionID}:${input.messageID}:${parsed.command}`
      if (sessionProcessedCommands.has(commandKey)) {
        return
      }
      sessionProcessedCommands.add(commandKey)

      const result = await executeSlashCommand(parsed, executorOptions)

      const idx = findSlashCommandPartIndex(output.parts)
      if (idx < 0) {
        return
      }

      if (!result.success || !result.replacementText) {
        return
      }

      if (parsed.command === "start-dayu") {
        updateSessionAgent(input.sessionID, "dayu")
      } else if (parsed.command === "start-baize") {
        updateSessionAgent(input.sessionID, "baize")
      } else if (parsed.command === "witty-diag") {
        const currentAgent = getSessionAgent(input.sessionID) ?? input.agent
        if (canSwitchToXuanyuan(currentAgent)) {
          updateSessionAgent(input.sessionID, "xuanyuan")
        }
      }

      if (shouldPreserveModelForCommand(parsed.command)) {
        const existing = getPinnedSessionModel(input.sessionID)
        const model =
          existing ??
          (input.model
            ? { providerID: input.model.providerID, modelID: input.model.modelID }
            : undefined)
        if (model) {
          if (!existing && input.model) {
            setPinnedSessionModel(input.sessionID, model)
          }
          output.message["model"] = {
            providerID: model.providerID,
            modelID: model.modelID,
          }
        }
      }

      const taggedContent = `${AUTO_SLASH_COMMAND_TAG_OPEN}\n${result.replacementText}\n${AUTO_SLASH_COMMAND_TAG_CLOSE}`
      output.parts[idx].text = taggedContent
    },

    "command.execute.before": async (
      input: CommandExecuteBeforeInput,
      output: CommandExecuteBeforeOutput
    ): Promise<void> => {
      const commandKey = `${input.sessionID}:${input.command}:${Date.now()}`
      if (sessionProcessedCommandExecutions.has(commandKey)) {
        return
      }

      const parsed = {
        command: input.command,
        args: input.arguments || "",
        raw: `/${input.command}${input.arguments ? " " + input.arguments : ""}`,
      }

      const result = await executeSlashCommand(parsed, executorOptions)

      if (!result.success || !result.replacementText) {
        return
      }

      sessionProcessedCommandExecutions.add(commandKey)

      const taggedContent = `${AUTO_SLASH_COMMAND_TAG_OPEN}\n${result.replacementText}\n${AUTO_SLASH_COMMAND_TAG_CLOSE}`

      const idx = findSlashCommandPartIndex(output.parts)
      if (idx >= 0) {
        output.parts[idx].text = taggedContent
      } else {
        output.parts.unshift({ type: "text", text: taggedContent })
      }

      if (input.command === "start-dayu") {
        updateSessionAgent(input.sessionID, "dayu")
      } else if (input.command === "start-baize") {
        updateSessionAgent(input.sessionID, "baize")
      } else if (input.command === "witty-diag") {
        const currentAgent = getSessionAgent(input.sessionID) ?? input.agent
        if (canSwitchToXuanyuan(currentAgent)) {
          updateSessionAgent(input.sessionID, "xuanyuan")
        }
      }

      if (shouldPreserveModelForCommand(input.command)) {
        const existing = getPinnedSessionModel(input.sessionID)
        const model =
          existing ??
          (input.model
            ? { providerID: input.model.providerID, modelID: input.model.modelID }
            : undefined)
        if (model) {
          if (!existing && input.model) {
            setPinnedSessionModel(input.sessionID, model)
          }
          output.message = output.message ?? {}
          output.message["model"] = {
            providerID: model.providerID,
            modelID: model.modelID,
          }
        }
      }

    },
  }
}
