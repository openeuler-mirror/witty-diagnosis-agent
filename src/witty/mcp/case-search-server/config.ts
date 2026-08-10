/**
 * Runtime configuration for the case-search MCP server.
 *
 * All values come from environment variables so they can be injected by the
 * OpenCode `type: "local"` MCP config (see `createBuiltinMcps`) without ever
 * passing secrets / kb_id through the model.
 *
 * Recognized environment variables:
 *   - CASE_API_BASE_URL  Base URL of the FastAPI RAG service, e.g. http://127.0.0.1:8000
 *   - CASE_KB_ID         kb_id of the known-issue knowledge base (required to be usable)
 *   - CASE_ACCESS_KEY    Optional access key. When set, sent as the `access_key` header.
 *   - CASE_API_TIMEOUT_MS  Optional per-request timeout in ms (default 15000)
 *   - CASE_TOP_K         Optional number of cases to retrieve (top_k, default 5).
 *                        A non-positive / non-numeric value falls back to 5.
 *   - CASE_CASES_DIR     Optional dir to write hit cases as a markdown file
 *                        (default ~/.witty-diagnosis-agent/shennong/cases)
 */
import { homedir } from "node:os"
import { join } from "node:path"

export interface CaseSearchConfig {
  /** Base URL of the FastAPI service, e.g. http://127.0.0.1:8000 (no trailing slash). */
  baseUrl: string
  /** kb_id of the known-issue knowledge base. Empty means the server is not usable. */
  kbId: string
  /** Optional access key sent as the `access_key` header. */
  accessKey?: string
  /** Per-request timeout in milliseconds. */
  timeoutMs: number
  /** Number of cases to retrieve from the RAG service (top_k). */
  topK: number
  /** Directory to write hit cases as a markdown file. */
  casesDir: string
}

const DEFAULT_BASE_URL = "http://127.0.0.1:8000"
const DEFAULT_TIMEOUT_MS = 15000
const DEFAULT_TOP_K = 5

/** Strip a single trailing slash so we can safely concatenate the path. */
function normalizeBaseUrl(raw: string | undefined): string {
  const value = (raw ?? "").trim() || DEFAULT_BASE_URL
  return value.endsWith("/") ? value.slice(0, -1) : value
}

/** Resolve config from `process.env` (or an injected env map for tests). */
export function loadCaseSearchConfig(
  env: Record<string, string | undefined> = process.env,
): CaseSearchConfig {
  const timeoutRaw = Number(env.CASE_API_TIMEOUT_MS)
  const timeoutMs =
    Number.isFinite(timeoutRaw) && timeoutRaw > 0 ? timeoutRaw : DEFAULT_TIMEOUT_MS

  const topKRaw = Number(env.CASE_TOP_K)
  const topK =
    Number.isInteger(topKRaw) && topKRaw > 0 ? topKRaw : DEFAULT_TOP_K

  const casesDir =
    (env.CASE_CASES_DIR ?? "").trim() ||
    join(homedir(), ".witty-diagnosis-agent", "shennong", "cases")

  return {
    baseUrl: normalizeBaseUrl(env.CASE_API_BASE_URL),
    kbId: (env.CASE_KB_ID ?? "").trim(),
    accessKey: (env.CASE_ACCESS_KEY ?? "").trim() || undefined,
    timeoutMs,
    topK,
    casesDir,
  }
}
