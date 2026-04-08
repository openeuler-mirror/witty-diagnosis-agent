import {
  detectSlashCommand,
  extractPromptText,
  findSlashCommandPartIndex,
} from "./detector"
import { executeSlashCommand, type ExecutorOptions } from "./executor"
import { log } from "../../shared"
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

      // Debug logging to diagnose slash command issues
      if (promptText.startsWith("/")) {
        log(`[auto-slash-command] chat.message hook received slash command`, {
          sessionID: input.sessionID,
          promptText: promptText.slice(0, 100),
        })
      }

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

      log(`[auto-slash-command] Detected: /${parsed.command}`, {
        sessionID: input.sessionID,
        args: parsed.args,
      })

      const result = await executeSlashCommand(parsed, executorOptions)

      const idx = findSlashCommandPartIndex(output.parts)
      if (idx < 0) {
        return
      }

      if (!result.success || !result.replacementText) {
        log(`[auto-slash-command] Command not found, skipping`, {
          sessionID: input.sessionID,
          command: parsed.command,
          error: result.error,
        })
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

      if (shouldPreserveModelForCommand(parsed.command) && input.model) {
        output.message["model"] = {
          providerID: input.model.providerID,
          modelID: input.model.modelID,
        }
      }

      const taggedContent = `${AUTO_SLASH_COMMAND_TAG_OPEN}\n${result.replacementText}\n${AUTO_SLASH_COMMAND_TAG_CLOSE}`
      output.parts[idx].text = taggedContent

      log(`[auto-slash-command] Replaced message with command template`, {
        sessionID: input.sessionID,
        command: parsed.command,
      })
    },

    "command.execute.before": async (
      input: CommandExecuteBeforeInput,
      output: CommandExecuteBeforeOutput
    ): Promise<void> => {
      const commandKey = `${input.sessionID}:${input.command}:${Date.now()}`
      if (sessionProcessedCommandExecutions.has(commandKey)) {
        return
      }

      log(`[auto-slash-command] command.execute.before received`, {
        sessionID: input.sessionID,
        command: input.command,
        arguments: input.arguments,
      })

      const parsed = {
        command: input.command,
        args: input.arguments || "",
        raw: `/${input.command}${input.arguments ? " " + input.arguments : ""}`,
      }

      const result = await executeSlashCommand(parsed, executorOptions)

      if (!result.success || !result.replacementText) {
        log(`[auto-slash-command] command.execute.before - command not found in our executor`, {
          sessionID: input.sessionID,
          command: input.command,
          error: result.error,
        })
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

      if (shouldPreserveModelForCommand(input.command) && input.model) {
        output.message = output.message ?? {}
        output.message["model"] = {
          providerID: input.model.providerID,
          modelID: input.model.modelID,
        }
      }

      log(`[auto-slash-command] command.execute.before - injected template`, {
        sessionID: input.sessionID,
        command: input.command,
      })
    },
  }
}
