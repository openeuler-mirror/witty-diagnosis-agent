import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

/**
 * Builds the OpenCode `type: "local"` MCP entry for the case-search server.
 *
 * The server is only enabled when a `CASE_KB_ID` is configured — without a kb_id
 * the `/json/search` calls cannot resolve, so we omit the server entirely rather
 * than register a non-functional tool.
 *
 * `kb_id` and credentials are passed via `environment` and injected into the
 * spawned stdio process; they never flow through the model.
 */
export type CaseSearchMcpConfig = {
  type: "local"
  command: string[]
  environment?: Record<string, string>
  enabled: boolean
}

/**
 * Resolve the absolute path to the built stdio entry (`case-search-cli.js`).
 *
 * The plugin bundles to `dist/index.js` while the stdio entry is a separate
 * tsup entry emitted at `dist/case-search-cli.js` (see tsup.config.ts). Both sit
 * directly under `dist/`, so resolving as a sibling of this module works for the
 * built output. When running from source (tsx/tests) this path will not exist —
 * that is fine, the config is only consumed by OpenCode against the build.
 */
function resolveCliEntry(): string {
  const here = dirname(fileURLToPath(import.meta.url))
  return join(here, "case-search-cli.js")
}

export function createCaseSearchMcpConfig(
  env: Record<string, string | undefined> = process.env,
): CaseSearchMcpConfig | undefined {
  const kbId = (env.CASE_KB_ID ?? "").trim()
  if (!kbId) return undefined

  const environment: Record<string, string> = { CASE_KB_ID: kbId }
  if (env.CASE_API_BASE_URL?.trim()) {
    environment.CASE_API_BASE_URL = env.CASE_API_BASE_URL.trim()
  }
  if (env.CASE_ACCESS_KEY?.trim()) {
    environment.CASE_ACCESS_KEY = env.CASE_ACCESS_KEY.trim()
  }
  if (env.CASE_API_TIMEOUT_MS?.trim()) {
    environment.CASE_API_TIMEOUT_MS = env.CASE_API_TIMEOUT_MS.trim()
  }
  if (env.CASE_TOP_K?.trim()) {
    environment.CASE_TOP_K = env.CASE_TOP_K.trim()
  }
  if (env.CASE_CASES_DIR?.trim()) {
    environment.CASE_CASES_DIR = env.CASE_CASES_DIR.trim()
  }

  return {
    type: "local",
    command: ["node", resolveCliEntry()],
    environment,
    enabled: true,
  }
}
