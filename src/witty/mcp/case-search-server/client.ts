import type { CaseSearchConfig } from "./config"
import type { CaseHit, SearchJsonsInput, SearchJsonsResult } from "./types"
import { writeCasesFile } from "./case-writer"

/**
 * Minimal client over the Knowledge-Base RAG REST API (POST /json/search).
 *
 * Endpoint used:
 *   POST /json/search  with SearchJsonRequest {
 *     need_trace: false,
 *     search_json_configs: [ SearchJsonConfig { kb_id, query, top_k, logical_expression? } ]
 *   }
 *
 * Design goals:
 *   - Pure-ish: takes config + an injectable fetch so tests can mock the network.
 *   - Graceful degradation: a missing kb_id or a failed request never throws to
 *     the caller; it returns a result carrying a `warning` instead, so the agent
 *     can keep planning even when the case library is unavailable.
 */
type FetchFn = typeof fetch

interface RawJson {
  id?: string
  kb_id?: string
  name?: string
  hit_count?: number
  content?: unknown
  content_after_preprocess?: unknown
}

interface SearchJsonApiResponse {
  code?: number
  message?: string
  result?: {
    jsons?: RawJson[]
  }
}

function toHit(kbId: string, json: RawJson): CaseHit {
  return {
    id: json.id ?? "",
    kbId: json.kb_id || kbId,
    name: (json.name ?? "").trim(),
    hitCount: typeof json.hit_count === "number" ? json.hit_count : 0,
    content: json.content ?? null,
    content_after_preprocess: json.content_after_preprocess ?? null,
  }
}

export class CaseSearchClient {
  constructor(
    private readonly config: CaseSearchConfig,
    private readonly fetchImpl: FetchFn = fetch,
  ) {}

  /**
   * Search the known-issue case library. Never throws — failures become `warning`.
   */
  async searchJsons(input: SearchJsonsInput): Promise<SearchJsonsResult> {
    const kbId = this.config.kbId
    const query = input.query?.trim() ?? ""

    const empty = (warning: string): SearchJsonsResult => ({
      kbId,
      query,
      cases_file: null,
      cases: [],
      warning,
    })

    if (!query) {
      return empty("empty query")
    }
    if (!kbId) {
      return empty("no kb_id configured (set CASE_KB_ID)")
    }

    const url = `${this.config.baseUrl}/json/search`
    const body = {
      need_trace: false,
      search_json_configs: [
        {
          kb_id: kbId,
          query,
          top_k: this.config.topK,
          ...(input.logicalExpression
            ? { logical_expression: input.logicalExpression }
            : {}),
        },
      ],
    }

    const headers: Record<string, string> = { "Content-Type": "application/json" }
    if (this.config.accessKey) headers["access_key"] = this.config.accessKey

    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), this.config.timeoutMs)
    try {
      const resp = await this.fetchImpl(url, {
        method: "POST",
        headers,
        body: JSON.stringify(body),
        signal: controller.signal,
      })

      if (!resp.ok) {
        return empty(`API /json/search returned HTTP ${resp.status}`)
      }

      const json = (await resp.json()) as SearchJsonApiResponse
      if (json.code !== undefined && json.code !== 200) {
        return empty(`API returned code ${json.code}: ${json.message ?? "unknown error"}`)
      }

      const jsons = json.result?.jsons ?? []
      const hits = jsons.map((j) => toHit(kbId, j))

      // Write full case bodies to a markdown file; only return the path + names
      // so large JSON never enters the model context.
      const casesFile = writeCasesFile(this.config.casesDir, query, kbId, hits)
      const cases = hits.map((h) => ({ id: h.id, name: h.name }))
      return { kbId, query, cases_file: casesFile, cases }
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err)
      return empty(`request failed: ${reason}`)
    } finally {
      clearTimeout(timer)
    }
  }
}
