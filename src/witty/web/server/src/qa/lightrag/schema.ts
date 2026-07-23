/**
 * 已知问题问答（QA）模块 · LightRAG 返回的规范化检索结果 schema 与容错解析。
 *
 * 设计依据：02 §2.2.2 / §4 / §5.1 与参考页 openEuler-ops-qa.html 的 KB 结构。
 *
 * 关键约束（与 01/02 的降级谱系对齐）：
 * - tool `state.output` 在 opencode 中是 string（cli/run/types.ts:95），结构化检索数据
 *   以 JSON 字符串承载，后端自行 JSON.parse + 校验 + 失败降级。
 * - 逐条引用 / 图谱 / 检索分层均可能缺失（取决于 LightRAG 实际返回，TBD-004），
 *   缺失项需优雅降级而非崩溃：本模块解析器一律「尽力规范化、缺字段置空」。
 *
 * 本文件零外部依赖（仅纯函数），供 web/server 直接 import。
 */

/** 双层检索：低层（精确实体/关系）+ 高层（主题/概念）。 */
export interface RetrievalLevels {
  low: string[];
  high: string[];
}

/** 引用来源类型徽标（对齐参考页 badge 配色）。 */
export type CitationType = "doc" | "inc" | "skill" | "kb";

/** 一条引用来源，对应答复正文中的 `[n]` 角标。 */
export interface Citation {
  id: number;
  type: CitationType;
  badge: string;
  title: string;
  origin: string;
  url: string;
  excerpt: string;
  entities: string[];
  relations: string[];
  /** 相关度 0–100。 */
  rel: number;
}

/** 知识图谱子图节点。 */
export interface GraphNode {
  id: string;
  /** 渲染坐标（LightRAG 若不返回布局，由前端兜底排布）。 */
  x: number;
  y: number;
  /** core=问题核心，ent=普通实体。 */
  t: "core" | "ent";
}

/** 知识图谱子图边（关系）。 */
export interface GraphEdge {
  a: string;
  b: string;
  l: string;
}

export interface GraphSubview {
  nodes: GraphNode[];
  edges: GraphEdge[];
}

/**
 * MCP adapter 规范化后写入 tool `state.output` 的结构（JSON 字符串）。
 * 后端解析此结构合成「检索 trace + 证据」。
 */
export interface LightragResult {
  /** 供 agent 组织答复的依据文本（真实路径下由 LLM 二次组织；mock 下直接作为答复流式）。 */
  answer_context: string;
  retrieval: RetrievalLevels;
  sources: Citation[];
  graph?: GraphSubview;
  followups?: string[];
  /** 命中为空（无答案）时为 true，前端走兜底（S-006/FR-010）。 */
  empty?: boolean;
}

function asStringArray(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return v.filter((x): x is string => typeof x === "string");
}

function asNumber(v: unknown, dflt = 0): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : dflt;
}

const CITATION_TYPES: ReadonlySet<string> = new Set(["doc", "inc", "skill", "kb"]);

function normalizeCitation(raw: unknown, index: number): Citation | null {
  if (!raw || typeof raw !== "object") return null;
  const o = raw as Record<string, unknown>;
  const type = CITATION_TYPES.has(String(o.type)) ? (o.type as CitationType) : "kb";
  return {
    id: Number.isFinite(Number(o.id)) ? Number(o.id) : index + 1,
    type,
    badge: typeof o.badge === "string" ? o.badge : "知识库",
    title: typeof o.title === "string" ? o.title : "未命名来源",
    origin: typeof o.origin === "string" ? o.origin : "",
    url: typeof o.url === "string" ? o.url : "",
    excerpt: typeof o.excerpt === "string" ? o.excerpt : "",
    entities: asStringArray(o.entities),
    relations: asStringArray(o.relations),
    rel: Math.max(0, Math.min(100, asNumber(o.rel, 0))),
  };
}

function normalizeGraph(raw: unknown): GraphSubview | undefined {
  if (!raw || typeof raw !== "object") return undefined;
  const o = raw as Record<string, unknown>;
  const nodesRaw = Array.isArray(o.nodes) ? o.nodes : [];
  const edgesRaw = Array.isArray(o.edges) ? o.edges : [];
  const nodes: GraphNode[] = nodesRaw
    .map((n): GraphNode | null => {
      if (!n || typeof n !== "object") return null;
      const r = n as Record<string, unknown>;
      if (typeof r.id !== "string") return null;
      return {
        id: r.id,
        x: asNumber(r.x, 0),
        y: asNumber(r.y, 0),
        t: r.t === "core" ? "core" : "ent",
      };
    })
    .filter((n): n is GraphNode => n !== null);
  const edges: GraphEdge[] = edgesRaw
    .map((e): GraphEdge | null => {
      if (!e || typeof e !== "object") return null;
      const r = e as Record<string, unknown>;
      if (typeof r.a !== "string" || typeof r.b !== "string") return null;
      return { a: r.a, b: r.b, l: typeof r.l === "string" ? r.l : "" };
    })
    .filter((e): e is GraphEdge => e !== null);
  if (nodes.length === 0) return undefined; // 无节点视作无图谱（优雅降级 S-009）
  return { nodes, edges };
}

/**
 * 把任意（可能不完整的）对象规范化为 LightragResult，缺字段一律置空、不抛错（S-009）。
 */
export function normalizeLightragResult(raw: unknown): LightragResult {
  const o = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const retrievalRaw = (o.retrieval && typeof o.retrieval === "object" ? o.retrieval : {}) as Record<string, unknown>;
  const sources = Array.isArray(o.sources)
    ? o.sources.map((s, i) => normalizeCitation(s, i)).filter((c): c is Citation => c !== null)
    : [];
  const answerContext = typeof o.answer_context === "string" ? o.answer_context : "";
  return {
    answer_context: answerContext,
    retrieval: { low: asStringArray(retrievalRaw.low), high: asStringArray(retrievalRaw.high) },
    sources,
    graph: normalizeGraph(o.graph),
    followups: asStringArray(o.followups),
    empty: o.empty === true || (answerContext.trim() === "" && sources.length === 0),
  };
}

/**
 * 解析 tool `state.output`（JSON 字符串）→ LightragResult；
 * 非 JSON / 非对象返回 null（S-008：MCP 返回格式异常 → 证据降级，正文不受影响）。
 */
export function parseLightragOutput(output: string | undefined | null): LightragResult | null {
  if (typeof output !== "string" || output.trim() === "") return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(output);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object") return null;
  return normalizeLightragResult(parsed);
}
