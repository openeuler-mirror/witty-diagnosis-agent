import type { ToolContextWithMetadata, OpencodeClient } from "./types"
import type { SessionMessage } from "./executor-types"
import { getTimingConfig } from "./timing"
import { log } from "../../shared/logger"
import { normalizeSDKResponse } from "../../shared"
import { getAgentConfigKey } from "../../shared/agent-display-names"

/** Nuwa-sub signals Xuanyuan must question the user; sync poll should return to parent without todo-continuation forcing further turns. */
const NUWA_SUB_HANDOFF_MARKER = "【需要交互】"

function lastAssistantTextContent(messages: SessionMessage[]): string {
  const lastAssistant = [...messages].reverse().find((m) => m.info?.role === "assistant")
  if (!lastAssistant?.parts?.length) return ""
  return lastAssistant.parts
    .filter((p) => p.type === "text" || p.type === "reasoning")
    .map((p) => (p as { text?: string }).text ?? "")
    .join("\n")
}

function nuwaSubAwaitingParentHandoff(agentToUse: string, messages: SessionMessage[]): boolean {
  if (getAgentConfigKey(agentToUse) !== "nuwa-sub") return false
  return lastAssistantTextContent(messages).includes(NUWA_SUB_HANDOFF_MARKER)
}

const NON_TERMINAL_FINISH_REASONS = new Set(["tool-calls", "unknown"])

export function isSessionComplete(messages: SessionMessage[]): boolean {
  let lastUser: SessionMessage | undefined
  let lastAssistant: SessionMessage | undefined

  for (let i = messages.length - 1; i >= 0; i--) {
    const msg = messages[i]
    if (!lastAssistant && msg.info?.role === "assistant") lastAssistant = msg
    if (!lastUser && msg.info?.role === "user") lastUser = msg
    if (lastUser && lastAssistant) break
  }

  if (!lastAssistant?.info?.finish) return false
  if (NON_TERMINAL_FINISH_REASONS.has(lastAssistant.info.finish)) return false
  if (!lastUser?.info?.id || !lastAssistant?.info?.id) return false
  return lastUser.info.id < lastAssistant.info.id
}

export async function pollSyncSession(
  ctx: ToolContextWithMetadata,
  client: OpencodeClient,
  input: {
    sessionID: string
    agentToUse: string
    toastManager: { removeTask: (id: string) => void } | null | undefined
    taskId: string | undefined
    anchorMessageCount?: number
  }
): Promise<string | null> {
  const syncTiming = getTimingConfig()
  const maxPollTimeMs = Math.max(syncTiming.MAX_POLL_TIME_MS, 50)
  const pollStart = Date.now()
  let pollCount = 0
  let timedOut = false

  log("[task] Starting poll loop", { sessionID: input.sessionID, agentToUse: input.agentToUse })

  while (Date.now() - pollStart < maxPollTimeMs) {
    if (ctx.abort?.aborted) {
      log("[task] Aborted by user", { sessionID: input.sessionID })
      if (input.toastManager && input.taskId) input.toastManager.removeTask(input.taskId)
      return `Task aborted.\n\nSession ID: ${input.sessionID}`
    }

    // Faster polling for the first few seconds to improve perceived latency
    const currentInterval = pollCount < 5 ? 200 : syncTiming.POLL_INTERVAL_MS
    await new Promise(resolve => setTimeout(resolve, currentInterval))
    pollCount++

    let statusResult: { data?: Record<string, { type: string }> }
    try {
      statusResult = await client.session.status()
    } catch (error) {
      log("[task] Poll status fetch failed, retrying", { sessionID: input.sessionID, error: String(error) })
      continue
    }
    const allStatuses = normalizeSDKResponse(statusResult, {} as Record<string, { type: string }>)
    const sessionStatus = allStatuses[input.sessionID]

    if (pollCount % 10 === 0) {
      log("[task] Poll status", {
        sessionID: input.sessionID,
        pollCount,
        elapsed: Math.floor((Date.now() - pollStart) / 1000) + "s",
        sessionStatus: sessionStatus?.type ?? "not_in_status",
      })
    }

    if (sessionStatus && sessionStatus.type !== "idle") {
      continue
    }

    let messagesResult: { data?: unknown } | SessionMessage[]
    try {
      messagesResult = await client.session.messages({ path: { id: input.sessionID } })
    } catch (error) {
      log("[task] Poll messages fetch failed, retrying", { sessionID: input.sessionID, error: String(error) })
      continue
    }
    const rawData = (messagesResult as { data?: unknown })?.data ?? messagesResult
    const msgs = Array.isArray(rawData) ? (rawData as SessionMessage[]) : []

    if (input.anchorMessageCount !== undefined && msgs.length <= input.anchorMessageCount) {
      continue
    }

    if (nuwaSubAwaitingParentHandoff(input.agentToUse, msgs)) {
      log("[task] Poll complete - nuwa-sub handoff to Xuanyuan (需要交互)", {
        sessionID: input.sessionID,
        pollCount,
      })
      break
    }

    if (isSessionComplete(msgs)) {
      log("[task] Poll complete - terminal finish detected", { sessionID: input.sessionID, pollCount })
      break
    }

    const lastAssistant = [...msgs].reverse().find((m) => m.info?.role === "assistant")
    const hasAssistantText = msgs.some((m) => {
      if (m.info?.role !== "assistant") return false
      const parts = m.parts ?? []
      return parts.some((p) => {
        if (p.type !== "text" && p.type !== "reasoning") return false
        const text = (p.text ?? "").trim()
        return text.length > 0
      })
    })

    if (!lastAssistant?.info?.finish && hasAssistantText) {
      log("[task] Poll complete - assistant text detected (fallback)", {
        sessionID: input.sessionID,
        pollCount,
      })
      break
    }
  }

  if (Date.now() - pollStart >= maxPollTimeMs) {
    timedOut = true
    log("[task] Poll timeout reached", { sessionID: input.sessionID, pollCount })
  }

  return timedOut
    ? `Poll timeout reached after ${maxPollTimeMs}ms for session ${input.sessionID}.

The delegated agent session may still be running. Do NOT fall back to re-executing the same diagnostic or shell commands yourself.
Instead, inform the user about the timeout, consider narrowing the task or resuming the delegated session, and keep execution within the appropriate subagent (e.g., Dayu/Kuafu).`
    : null
}
