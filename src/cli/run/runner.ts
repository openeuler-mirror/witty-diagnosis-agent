import pc from "picocolors"
import { readFileSync, writeFileSync, existsSync, readdirSync } from "node:fs"
import { join, resolve, dirname, basename, extname } from "node:path"
import { homedir } from "node:os"
import { marked } from "marked"
import type { RunOptions, RunContext } from "./types"
import { createEventState, processEvents, serializeError } from "./events"
import { loadPluginConfig } from "../../plugin-config"
import { createServerConnection } from "./server-connection"
import { resolveSession } from "./session-resolver"
import { createJsonOutputManager } from "./json-output"
import { executeOnCompleteHook } from "./on-complete-hook"
import { resolveRunAgent } from "./agent-resolver"
import { pollForCompletion } from "./poll-for-completion"
import { loadAgentProfileColors } from "./agent-profile-colors"
import { suppressRunInput } from "./stdin-suppression"
import { createTimestampedStdoutController } from "./timestamp-output"

export { resolveRunAgent }

const EVENT_PROCESSOR_SHUTDOWN_TIMEOUT_MS = 2_000

export async function waitForEventProcessorShutdown(
  eventProcessor: Promise<void>,
  timeoutMs = EVENT_PROCESSOR_SHUTDOWN_TIMEOUT_MS,
): Promise<void> {
  const completed = await Promise.race([
    eventProcessor.then(() => true),
    new Promise<boolean>((resolve) => setTimeout(() => resolve(false), timeoutMs)),
  ])

  void completed
}

export async function run(options: RunOptions): Promise<number> {
  process.env.OPENCODE_CLI_RUN_MODE = "true"

  const startTime = Date.now()
  const {
    message,
    directory = process.cwd(),
  } = options

  const jsonManager = options.json ? createJsonOutputManager() : null
  if (jsonManager) jsonManager.redirectToStderr()
  const timestampOutput = options.json || options.timestamp === false
    ? null
    : createTimestampedStdoutController()
  timestampOutput?.enable()

  const pluginConfig = loadPluginConfig(directory, { command: "run" })
  const resolvedAgent = resolveRunAgent(options, pluginConfig)
  const abortController = new AbortController()

  try {
    const { client, cleanup: serverCleanup } = await createServerConnection({
      port: options.port,
      attach: options.attach,
      signal: abortController.signal,
    })

    const cleanup = () => {
      serverCleanup()
    }

    const restoreInput = suppressRunInput()
    const handleSigint = () => {
      console.log(pc.yellow("\nInterrupted. Shutting down..."))
      restoreInput()
      cleanup()
      process.exit(130)
    }

    process.on("SIGINT", handleSigint)

    try {
      const sessionID = await resolveSession({
        client,
        sessionId: options.sessionId,
        directory,
      })

      console.log(pc.dim(`Session: ${sessionID}`))

      const ctx: RunContext = {
        client,
        sessionID,
        directory,
        abortController,
        verbose: options.verbose ?? false,
      }
      const events = await client.event.subscribe({ query: { directory } })
      const eventState = createEventState()
      eventState.agentColorsByName = await loadAgentProfileColors(client)
      const eventProcessor = processEvents(ctx, events.stream, eventState).catch(
        () => {},
      )

      await client.session.promptAsync({
        path: { id: sessionID },
        body: {
          agent: resolvedAgent,
          tools: {
            question: false,
          },
          parts: [{ type: "text", text: message }],
        },
        query: { directory },
      })
      const exitCode = await pollForCompletion(ctx, eventState, abortController)

      // Auto-convert unconverted MD reports in baize/reports to HTML
      try {
        const wittyHome = join(homedir(), ".witty-diagnosis-agent")
        const reportsDir = join(wittyHome, "baize", "reports")
        if (existsSync(reportsDir)) {
          for (const file of readdirSync(reportsDir)) {
            if (!file.endsWith(".md")) continue
            const htmlFile = file.slice(0, -3) + ".html"
            if (existsSync(join(reportsDir, htmlFile))) continue
            const mdPath = join(reportsDir, file)
            const htmlPath = join(reportsDir, htmlFile)
            const mdContent = readFileSync(mdPath, "utf-8")
            const htmlContent = marked.parse(mdContent, { async: false }) as string
            const fullHtml = `<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="UTF-8"><title>${file.replace(/_/g, " ")}</title>
<style>
body{max-width:960px;margin:0 auto;padding:20px;font-family:-apple-system,BlinkMacSystemFont,sans-serif;line-height:1.6;color:#333}
pre{background:#f5f5f5;padding:12px;border-radius:6px;overflow-x:auto}
code{background:#f0f0f0;padding:2px 5px;border-radius:3px}
table{border-collapse:collapse;width:100%;margin:16px 0}
th,td{border:1px solid #ddd;padding:8px;text-align:left}
th{background:#f0f0f0}
h1,h2,h3{color:#1a1a1a;margin-top:24px}
blockquote{border-left:4px solid #ddd;padding-left:16px;color:#666}
hr{border:none;border-top:2px solid #eee;margin:24px 0}
</style></head>
<body>${htmlContent}</body></html>`
            writeFileSync(htmlPath, fullHtml, "utf-8")
            console.log(pc.green(`✅ HTML report generated: ${htmlPath}`))
          }
        }
      } catch {
        // Non-fatal: auto-conversion is best-effort
      }

      // Abort the event stream to stop the processor
      abortController.abort()

      await waitForEventProcessorShutdown(eventProcessor)
      cleanup()

      const durationMs = Date.now() - startTime

      if (options.onComplete) {
        await executeOnCompleteHook({
          command: options.onComplete,
          sessionId: sessionID,
          exitCode,
          durationMs,
          messageCount: eventState.messageCount,
        })
      }

      if (jsonManager) {
        jsonManager.emitResult({
          sessionId: sessionID,
          success: exitCode === 0,
          durationMs,
          messageCount: eventState.messageCount,
          summary: eventState.lastPartText.slice(0, 200) || "Run completed",
        })
      }

      return exitCode
    } catch (err) {
      cleanup()
      throw err
    } finally {
      process.removeListener("SIGINT", handleSigint)
      restoreInput()
    }
  } catch (err) {
    if (jsonManager) jsonManager.restore()
    timestampOutput?.restore()
    if (err instanceof Error && err.name === "AbortError") {
      return 130
    }
    console.error(pc.red(`Error: ${serializeError(err)}`))
    return 1
  } finally {
    timestampOutput?.restore()
  }
}
