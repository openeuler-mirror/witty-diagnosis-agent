/**
 * 已知问题问答（QA）模块 · LightRAG 检索客户端。
 *
 * 两种形态（由 config.lightrag.mock 决定，见 02 §6.3）：
 *  - mock：返回与参考页 openEuler-ops-qa.html 同构的内置知识（本期默认，LightRAG 未灌库/未就绪时联调用）。
 *  - real：桥接 LightRAG REST `/query`（local/global 双层），规范化为 LightragResult。
 *
 * 设计依据：02 §2.2.2（双层来源映射、lazy 连接、端点不可达返回结构化 error）。
 * 本文件零外部依赖（仅 node 内置 fetch，Node ≥20），供 web/server 直接 import。
 */

import { normalizeLightragResult, type Citation, type LightragResult } from "./schema.js";

export type LightragQueryMode = "hybrid" | "local" | "global" | "naive" | "mix" | "bypass";

export interface LightragClientConfig {
  /** true=用内置 mock 知识；false=对接真实 LightRAG REST。 */
  mock: boolean;
  endpoint?: string;
  apiKey?: string;
  /** API Key 请求头名；LightRAG Web/API 常见为 X-API-Key。 */
  apiKeyHeader?: string;
  /** 单次检索超时（ms）。 */
  timeoutMs?: number;
  /** LightRAG /query 默认 mode；当前版本推荐 mix。 */
  defaultMode?: LightragQueryMode;
  /** 期望回答格式；透传给 LightRAG。 */
  responseType?: string;
  /** 是否附带引用 chunk 原文，便于前端证据卡片展示。 */
  includeChunkContent?: boolean;
}

export interface LightragQueryInput {
  question: string;
  /** 双层检索模式提示；real 路径据此选择 LightRAG mode。 */
  mode?: LightragQueryMode;
  /** 会话标识：mock 客户端据此保留多轮上下文（real 路径忽略，上下文由 opencode session 续跑承载）。 */
  sessionId?: string;
}

/** LightRAG 不可达 / 超时 / 异常返回时抛出，由 driver 降级（S-007）。 */
export class LightragUnavailableError extends Error {
  constructor(
    message: string,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = "LightragUnavailableError";
  }
}

export interface LightragClient {
  query(input: LightragQueryInput): Promise<LightragResult>;
}

// ----------------------------------------------------------------------------
// Mock 知识库（移植自参考页 KB；answer 用纯文本 + [n] 角标 + **加粗** + `代码`）
// ----------------------------------------------------------------------------

interface MockEntry {
  keywords: string[];
  retrieval: LightragResult["retrieval"];
  answer: string;
  sources: Citation[];
  graph: NonNullable<LightragResult["graph"]>;
  followups: string[];
}

const KB: MockEntry[] = [
  {
    keywords: ["firewalld", "reload", "断网", "容器无法访问", "iptables"],
    retrieval: {
      low: ["firewalld", "iptables：DOCKER 链", "iptables：DOCKER-USER 链", "容器 NAT/转发规则", "firewalld reload → 重建 iptables 规则"],
      high: ["容器网络中断", "防火墙与容器规则冲突"],
    },
    answer: [
      "这是 openEuler / CentOS 上高频的「防火墙与容器规则冲突」问题，容器进程本身正常，但网络全断。",
      "**根因：** firewalld 在 `reload` 时会重建整张 iptables 规则表，从而清空 Docker 启动时注入的自定义链（`DOCKER`、`DOCKER-USER` 等）[1]。这些链承载了容器的 NAT 与转发规则，链一旦丢失，容器就无法做地址转换，表现为「进程在跑、网络不通」[2]。",
      "**快速验证：** 执行 `iptables -L DOCKER -n`，若该链为空或不存在，即可确认[2]。",
      "**恢复手段（按优先级）：**\n1. 【立即】重启 docker 让其重新注入规则：`systemctl restart docker`[2]\n2. 【根治】把 docker 规则纳入 firewalld 托管，或调整启动顺序使 docker 在 firewalld 之后启动[3]\n3. 【预防】生产环境固定二者依赖关系，避免对线上裸跑 `firewall-cmd --reload`[3]",
    ].join("\n\n"),
    sources: [
      { id: 1, type: "doc", badge: "官方文档", title: "容器网络配置指南 · iptables 与 firewalld 协同", origin: "docs.openeuler.org", url: "https://docs.openeuler.org/zh/.../container-network.html", excerpt: "当 firewalld 执行 reload 时，会清除并重建全部 iptables 规则，Docker 注入的 DOCKER、DOCKER-USER 链将被一并清空，需重启容器运行时或重新加载网络规则方可恢复。", entities: ["firewalld", "iptables", "DOCKER 链"], relations: ["firewalld reload → 重建 iptables"], rel: 96 },
      { id: 2, type: "inc", badge: "故障案例", title: "INC-20241108 firewalld reload 致容器网络中断", origin: "内部知识库 · 事件库", url: "kb.internal/incidents/INC-20241108", excerpt: "现场 docker ps 全部 Up，容器内 ping 外网超时。执行 iptables -L DOCKER -n 返回空链，确认规则被 firewalld 清空；systemctl restart docker 后 90 秒内恢复。", entities: ["DOCKER 链", "容器 NAT"], relations: ["规则丢失 → 网络不通"], rel: 91 },
      { id: 3, type: "skill", badge: "运维 Skill", title: "docker-fault-diagnosis · network_iptables.md", origin: "运维 Skill 库", url: "skill://docker-fault-diagnosis/references/network_iptables.md", excerpt: "长期方案：将 docker.service 配置为 After=firewalld.service，或启用 firewalld 的 docker zone 托管；避免在业务时段对线上主机执行 reload。", entities: ["docker.service", "firewalld zone"], relations: ["启动顺序 → 规则保留"], rel: 84 },
    ],
    graph: {
      nodes: [
        { id: "firewalld", x: 90, y: 60, t: "ent" },
        { id: "iptables", x: 250, y: 55, t: "ent" },
        { id: "DOCKER 链", x: 255, y: 165, t: "ent" },
        { id: "容器网络", x: 95, y: 175, t: "core" },
        { id: "docker.service", x: 120, y: 270, t: "ent" },
      ],
      edges: [
        { a: "firewalld", b: "iptables", l: "reload 重建" },
        { a: "iptables", b: "DOCKER 链", l: "清空" },
        { a: "DOCKER 链", b: "容器网络", l: "承载 NAT" },
        { a: "docker.service", b: "DOCKER 链", l: "注入" },
      ],
    },
    followups: ["怎么彻底避免 firewalld 和 docker 的规则冲突？", "DOCKER 链和 DOCKER-USER 链有什么区别？"],
  },
  {
    keywords: ["overlay", "overlay2", "ftype", "启动失败", "升级 docker", "存储驱动"],
    retrieval: {
      low: ["overlay2 存储驱动", "XFS 文件系统", "ftype=0", "d_type 支持", "XFS ftype=0 → overlay2 不支持"],
      high: ["容器启动失败", "存储驱动兼容性"],
    },
    answer: [
      "典型的「XFS + overlay2 兼容性」问题，常在 CentOS 7 升级链路上出现，openEuler 同样适用。",
      "**根因：** overlay2 依赖文件系统的 `d_type` 能力。若承载 `/var/lib/docker` 的 XFS 分区在格式化时 `ftype=0`，则不支持 d_type，overlay2 无法工作，容器全部启动失败[1]。",
      "**快速验证：** `xfs_info /var/lib/docker | grep ftype`，若显示 `ftype=0` 即命中[2]。",
      "**处置：**\n1. 【根治】用 `ftype=1` 重新格式化该分区（需备份数据）[1]\n2. 【临时】切换到 devicemapper 等其它存储驱动可临时绕过，但不建议长期使用[2]",
    ].join("\n\n"),
    sources: [
      { id: 1, type: "doc", badge: "官方文档", title: "容器存储驱动选型与 overlay2 要求", origin: "docs.openeuler.org", url: "https://docs.openeuler.org/zh/.../storage-driver.html", excerpt: "overlay2 要求底层文件系统支持 d_type。XFS 必须以 ftype=1 创建，否则 overlay2 无法挂载，容器创建会失败。", entities: ["overlay2", "XFS", "ftype"], relations: ["ftype=1 → 支持 d_type"], rel: 95 },
      { id: 2, type: "skill", badge: "运维 Skill", title: "docker-fault-diagnosis · storage_overlay.md", origin: "运维 Skill 库", url: "skill://docker-fault-diagnosis/references/storage_overlay.md", excerpt: "高危场景速查：CentOS 7 + XFS + Docker 升级常因 ftype=0 不支持 overlay2 导致全量容器启动失败；快速验证命令 xfs_info | grep ftype。", entities: ["devicemapper", "xfs_info"], relations: ["ftype=0 → 启动失败"], rel: 88 },
    ],
    graph: {
      nodes: [
        { id: "docker 升级", x: 95, y: 55, t: "ent" },
        { id: "overlay2", x: 250, y: 70, t: "ent" },
        { id: "XFS", x: 255, y: 180, t: "ent" },
        { id: "容器启动失败", x: 95, y: 185, t: "core" },
        { id: "ftype=0", x: 255, y: 275, t: "ent" },
      ],
      edges: [
        { a: "docker 升级", b: "overlay2", l: "默认驱动" },
        { a: "overlay2", b: "XFS", l: "依赖 d_type" },
        { a: "XFS", b: "ftype=0", l: "格式化参数" },
        { a: "ftype=0", b: "容器启动失败", l: "不支持" },
      ],
    },
    followups: ["ftype=1 重新格式化会丢数据吗？怎么平滑迁移？", "怎么提前巡检全集群的 XFS ftype 配置？"],
  },
  {
    keywords: ["137", "oom", "oomkilled", "重启", "xmx", "exited", "java 容器"],
    retrieval: {
      low: ["ExitCode 137", "OOMKilled", "cgroup 内存限制", "JVM Xmx", "JVM 未感知 cgroup limit"],
      high: ["容器循环重启", "内存配额与 JVM 配置不匹配"],
    },
    answer: [
      "这是「JVM 未感知 cgroup 限制」导致的容器级 OOM，和宿主机整体内存是否充足无关。",
      "**根因：** `Exited(137)` = 128 + 9（SIGKILL），通常是容器触发了 cgroup 内存上限被 OOMKilled[1]。若 JVM 的 `-Xmx` 大于容器 `--memory` 限制，或旧版 JDK 未启用 cgroup 感知，JVM 会按宿主机物理内存设堆，超过容器配额即被杀[2]。",
      "**快速验证：** 对比 `docker inspect` 的 Memory 限制与 JVM 启动参数；查 `dmesg | grep -i oom` 是否有 OOM 记录[1]。",
      "**处置：**\n1. 【根治】显式设置 `-Xmx` 低于容器内存上限，或升级 JDK 并启用容器感知[2]\n2. 【预防】为容器设置合理的 `--memory` 并预留堆外内存余量[2]",
    ].join("\n\n"),
    sources: [
      { id: 1, type: "inc", badge: "故障案例", title: "INC-20250216 Java 容器 Exited(137) 循环重启", origin: "内部知识库 · 事件库", url: "kb.internal/incidents/INC-20250216", excerpt: "容器反复 Exited(137)，宿主机 free 充足。dmesg 出现 Memory cgroup out of memory，确认为容器级 OOMKilled，而非宿主机内存耗尽。", entities: ["ExitCode 137", "OOMKilled", "cgroup"], relations: ["超配额 → SIGKILL"], rel: 94 },
      { id: 2, type: "skill", badge: "运维 Skill", title: "docker-fault-diagnosis · resource_oom.md", origin: "运维 Skill 库", url: "skill://docker-fault-diagnosis/references/resource_oom.md", excerpt: "JVM 若未感知 cgroup 限制，会按宿主机物理内存设置堆，-Xmx 大于容器 --memory 即必然被 OOMKill；新版 JDK 需启用容器感知。", entities: ["JVM", "-Xmx", "--memory"], relations: ["Xmx > limit → OOM"], rel: 90 },
    ],
    graph: {
      nodes: [
        { id: "JVM -Xmx", x: 95, y: 58, t: "ent" },
        { id: "cgroup limit", x: 255, y: 62, t: "ent" },
        { id: "OOMKilled", x: 255, y: 175, t: "ent" },
        { id: "容器循环重启", x: 95, y: 185, t: "core" },
        { id: "Exited(137)", x: 120, y: 275, t: "ent" },
      ],
      edges: [
        { a: "JVM -Xmx", b: "cgroup limit", l: "超过" },
        { a: "cgroup limit", b: "OOMKilled", l: "触发" },
        { a: "OOMKilled", b: "Exited(137)", l: "SIGKILL" },
        { a: "OOMKilled", b: "容器循环重启", l: "导致" },
      ],
    },
    followups: ["怎么让旧版 JDK 也能感知 cgroup 内存限制？", "如何批量巡检容器 Xmx 与 memory 限制是否匹配？"],
  },
];

/** 兜底：未命中知识库时仍给带引用的通用方法论答复（S-006 之外的「弱命中」演示）。 */
const FALLBACK: Omit<MockEntry, "keywords"> = {
  retrieval: { low: ["关键词实体抽取", "知识库向量召回"], high: ["运维问题归类"] },
  answer: [
    "已在知识库中检索与你问题最相关的资料。下面是综合多个来源的回答（请结合现场核实）：",
    "建议按「先定位、再恢复、后加固」的顺序处理：先用对应命令确认现象与根因[1]，再执行最小化恢复操作，最后补齐预防措施[1]。如需更精确的答案，可补充具体报错信息或日志片段。",
  ].join("\n\n"),
  sources: [
    { id: 1, type: "kb", badge: "知识库", title: "运维通用排查方法论 · 定位/恢复/加固", origin: "内部知识库", url: "kb.internal/handbook/triage-method", excerpt: "通用排查三段式：先定位（验证现象+锁定根因）→ 再恢复（最小化操作）→ 后加固（消除复发条件），避免在未定位时盲目重启。", entities: ["排查方法论"], relations: ["定位 → 恢复 → 加固"], rel: 72 },
  ],
  graph: {
    nodes: [
      { id: "问题", x: 95, y: 90, t: "core" },
      { id: "定位", x: 255, y: 55, t: "ent" },
      { id: "恢复", x: 265, y: 150, t: "ent" },
      { id: "加固", x: 160, y: 255, t: "ent" },
    ],
    edges: [
      { a: "问题", b: "定位", l: "先" },
      { a: "定位", b: "恢复", l: "再" },
      { a: "恢复", b: "加固", l: "后" },
    ],
  },
  followups: ["能帮我把这个问题整理成故障工单吗？", "有没有相关的历史故障案例？"],
};

function matchKb(question: string): MockEntry | null {
  const low = question.toLowerCase();
  for (const entry of KB) {
    if (entry.keywords.some((k) => low.includes(k.toLowerCase()))) return entry;
  }
  return null;
}

class MockLightragClient implements LightragClient {
  /** 按会话记忆上次命中的主题，支撑多轮上下文（FR-005 的 mock 演示）。 */
  private memory = new Map<string, Omit<MockEntry, "keywords">>();

  async query(input: LightragQueryInput): Promise<LightragResult> {
    const hit = matchKb(input.question);
    let entry: Omit<MockEntry, "keywords"> | null = hit;
    let contextual = false;

    // 未命中关键词但同会话有上文主题 → 结合上文续答（多轮上下文）
    if (!entry && input.sessionId && this.memory.has(input.sessionId)) {
      entry = this.memory.get(input.sessionId)!;
      contextual = true;
    }
    if (!entry) entry = FALLBACK;

    // 记住非兜底主题，供后续追问续跑
    if (input.sessionId && entry !== FALLBACK) this.memory.set(input.sessionId, entry);

    const answer = contextual ? `（结合上文继续）\n\n${entry.answer}` : entry.answer;
    return normalizeLightragResult({
      answer_context: answer,
      retrieval: entry.retrieval,
      sources: entry.sources,
      graph: entry.graph,
      followups: entry.followups,
      empty: false,
    });
  }
}

// ----------------------------------------------------------------------------
// Real LightRAG REST 客户端（桥接 /query）。本期 mock 优先，真实路径供后续联调。
// ----------------------------------------------------------------------------

class RestLightragClient implements LightragClient {
  constructor(private readonly cfg: LightragClientConfig) {}

  async query(input: LightragQueryInput): Promise<LightragResult> {
    const endpoint = this.cfg.endpoint?.replace(/\/+$/, "");
    if (!endpoint) throw new LightragUnavailableError("LIGHTRAG_ENDPOINT 未配置");
    const url = `${endpoint}/query`;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.cfg.timeoutMs ?? 30000);
    const body = JSON.stringify({
      query: input.question,
      mode: resolveQueryMode(input.mode, this.cfg.defaultMode),
      stream: false,
      include_references: true,
      include_chunk_content: this.cfg.includeChunkContent ?? true,
      response_type: this.cfg.responseType ?? "Multiple Paragraphs",
    });
    try {
      const res = await fetchWithAuthFallback(url, body, this.cfg, controller.signal);
      if (!res.ok) throw new LightragUnavailableError(await formatHttpError(res));
      const raw = (await res.json()) as unknown;
      // 兼容 LightRAG 0312+ 常见契约：{ response, references[] }。
      return normalizeLightragResult(mapRestResponse(raw));
    } catch (err) {
      if (err instanceof LightragUnavailableError) throw err;
      throw new LightragUnavailableError("LightRAG 检索失败或超时", err);
    } finally {
      clearTimeout(timer);
    }
  }
}

async function fetchWithAuthFallback(
  url: string,
  body: string,
  cfg: LightragClientConfig,
  signal: AbortSignal,
): Promise<Response> {
  const primaryHeaders = {
    "Content-Type": "application/json",
    ...buildAuthHeaders(cfg),
  };
  const primaryRes = await fetch(url, {
    method: "POST",
    headers: primaryHeaders,
    body,
    signal,
  });
  if (primaryRes.status !== 401 || !shouldRetryWithApiKeyHeader(cfg)) return primaryRes;

  return fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-API-Key": cfg.apiKey!.trim(),
    },
    body,
    signal,
  });
}

function buildAuthHeaders(cfg: LightragClientConfig): Record<string, string> {
  const apiKey = cfg.apiKey?.trim();
  if (!apiKey) return {};

  const headerName = (cfg.apiKeyHeader || "X-API-Key").trim();
  if (!headerName) return {};

  if (headerName.toLowerCase() === "authorization") {
    return {
      Authorization: /^bearer\s+/i.test(apiKey) ? apiKey : `Bearer ${apiKey}`,
    };
  }

  return { [headerName]: apiKey };
}

function shouldRetryWithApiKeyHeader(cfg: LightragClientConfig): boolean {
  const apiKey = cfg.apiKey?.trim();
  if (!apiKey) return false;
  return (cfg.apiKeyHeader || "X-API-Key").trim().toLowerCase() === "authorization";
}

function resolveQueryMode(inputMode: LightragQueryMode | undefined, defaultMode: LightragQueryMode | undefined): LightragQueryMode {
  return inputMode ?? defaultMode ?? "mix";
}

async function formatHttpError(res: Response): Promise<string> {
  let detail = "";
  try {
    const raw = (await res.json()) as Record<string, unknown>;
    if (typeof raw.detail === "string" && raw.detail.trim()) detail = raw.detail.trim();
    else if (typeof raw.error === "string" && raw.error.trim()) detail = raw.error.trim();
  } catch {
    // ignore non-JSON error bodies
  }
  return detail ? `LightRAG /query HTTP ${res.status}: ${detail}` : `LightRAG /query HTTP ${res.status}`;
}

function mapReferences(raw: unknown): Citation[] {
  if (!Array.isArray(raw)) return [];

  return raw
    .map((item, index): Citation | null => {
      if (!item || typeof item !== "object") return null;
      const ref = item as Record<string, unknown>;
      const path = typeof ref.file_path === "string" ? ref.file_path : "";
      const title = path ? basenameLike(path) : `Reference ${index + 1}`;
      const content = Array.isArray(ref.content) ? ref.content.find((entry): entry is string => typeof entry === "string" && entry.trim() !== "") : undefined;
      const refId = typeof ref.reference_id === "string" || typeof ref.reference_id === "number" ? Number(ref.reference_id) : index + 1;

      return {
        id: Number.isFinite(refId) ? refId : index + 1,
        type: "kb",
        badge: "LightRAG",
        title,
        origin: inferOrigin(path),
        url: path,
        excerpt: content ?? "",
        entities: [],
        relations: [],
        rel: 0,
      };
    })
    .filter((citation): citation is Citation => citation !== null);
}

function basenameLike(path: string): string {
  const trimmed = path.replace(/[?#].*$/, "").replace(/\/+$/, "");
  if (!trimmed) return "Reference";
  const parts = trimmed.split("/");
  return parts[parts.length - 1] || trimmed;
}

function inferOrigin(path: string): string {
  if (!path) return "";
  try {
    return new URL(path).host || path;
  } catch {
    return path;
  }
}

/**
 * 把 LightRAG `/query` 的原始响应映射到本模块规范结构。
 * LightRAG 不同版本返回差异较大（TBD-004）：此处做最宽松映射，未知字段交由 normalize 兜底。
 */
function mapRestResponse(raw: unknown): unknown {
  if (!raw || typeof raw !== "object") return {};
  const o = raw as Record<string, unknown>;
  const mappedReferences = mapReferences(o.references);
  const answer = o.answer_context ?? o.response ?? o.answer ?? "";
  // 常见形态：{ response: "...", data: {...} } 或直接结构化对象。优先透传结构化字段。
  return {
    answer_context: answer,
    retrieval: o.retrieval ?? {},
    sources: o.sources ?? mappedReferences,
    graph: o.graph ?? o.knowledge_graph,
    followups: o.followups ?? o.follow_up_questions ?? [],
    empty: o.empty ?? (typeof answer === "string" && answer.trim() === "" && mappedReferences.length === 0),
  };
}

/** 工厂：按配置返回 mock / real 客户端。 */
export function createLightragClient(cfg: LightragClientConfig): LightragClient {
  return cfg.mock ? new MockLightragClient() : new RestLightragClient(cfg);
}
