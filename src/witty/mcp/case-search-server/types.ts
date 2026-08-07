/**
 * Shared types for the case-search MCP server.
 *
 * The server wraps the Knowledge-Base RAG REST API (FastAPI):
 *   - POST /json/search → structured (known-issue case) retrieval
 *
 * It is consumed by the Shennong (神农) known-issue analysis sub-agent.
 */

/**
 * Logical filter expression for /json/search, mirroring the FastAPI
 * `LogicalExpression` schema. A node is either a logical group (operator over
 * nested expressions) or a leaf `Condition`. We keep it permissive (the skill
 * that produces it owns the exact shape) and forward it verbatim to the API.
 */
export interface LogicalExpression {
  operator: string
  expressions: Array<LogicalExpression | Condition | Record<string, unknown>>
}

/** A single leaf filter condition (FastAPI `Condition`). */
export interface Condition {
  field: string | string[]
  type?: string
  operator: string
  value?: unknown
}

/** Input for a single known-case search. kb_id is injected from config, never from the model. */
export interface SearchJsonsInput {
  /** Natural-language query derived from log / anomaly analysis. */
  query: string
  /** Optional structured filter, produced by the euler-rag-json-search skill. */
  logicalExpression?: LogicalExpression
}

/** A normalized search hit returned to the agent. */
export interface CaseHit {
  /** Document id of the matched json case. */
  id: string
  /** kb_id the hit belongs to. */
  kbId: string
  /** Human-readable name of the case, when present. */
  name: string
  /** How many times this case has been hit (relevance proxy from the API). */
  hitCount: number
  /** The structured case payload (FastAPI Json.content), passed through verbatim. */
  content: unknown
  /** The preprocessed case payload (FastAPI Json.content_after_preprocess). */
  content_after_preprocess: unknown
}

/** Lightweight identifier for a hit case returned to the model (no bodies). */
export interface CaseRef {
  /** Document id of the matched json case. */
  id: string
  /** The case name. */
  name: string
}

/**
 * Result handed back to the model.
 *
 * Case bodies are deliberately NOT inlined: they are written to `cases_file`
 * and only the path + light `{id, name}` list travel through the context.
 */
export interface SearchJsonsResult {
  kbId: string
  query: string
  /** Absolute path of the markdown file holding the hit case bodies; null when no hits. */
  cases_file: string | null
  /** Lightweight hit list: document id + case name. */
  cases: CaseRef[]
  /** Present when the search degraded (no kb configured, API failure, empty query). */
  warning?: string
}
