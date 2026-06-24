// 与后端 DTO 对齐（server/src/types.ts）。

export type TaskMode = "online" | "offline";
export type TaskStatus = "queued" | "running" | "succeeded" | "failed" | "canceled";

export const STAGES = ["排队中", "数据采集", "数据分析", "故障定位", "生成报告", "完成"] as const;

export interface OnlineTarget {
  hostIp: string;
  sshUser: string;
  sshPort: number;
}
export interface OfflineFile {
  id: string;
  filename: string;
  size: number;
}

export interface Task {
  id: string;
  ownerId: string;
  title: string;
  faultTime: string;
  mode: TaskMode;
  status: TaskStatus;
  progress: number;
  currentStage: string | null;
  failReason: string | null;
  createdAt: number;
  updatedAt: number;
  expireAt: number;
  target?: OnlineTarget;
  files?: OfflineFile[];
  rating?: number;
  hasReport: boolean;
}

export interface TaskDetail extends Task {
  logs: { time: string; text: string }[];
}

export interface CreateTaskBody {
  title: string;
  faultTime: string;
  mode: TaskMode;
  // online
  hostIp?: string;
  sshUser?: string;
  sshPassword?: string;
  sshPort?: number;
  connectivityVerified?: boolean;
  // offline
  uploadIds?: string[];
  logPath?: string;
}

export interface SessionUser {
  id: string;
  subject: string;
  displayName: string;
}

export type ReportBlock =
  | { t: "kv"; rows: [string, string][] }
  | { t: "table"; head: string[]; rows: string[][] }
  | { t: "p"; html: string }
  | { t: "ul"; items: string[] }
  | { t: "ol"; items: string[] }
  | { t: "code"; text: string }
  | { t: "tone"; tone: "warn" | "danger" | "ok" | "info"; html: string }
  | { t: "chain"; nodes: { text: string; bad?: boolean }[] }
  | { t: "timeline"; items: { time: string; text: string }[] }
  | { t: "sub"; id: string; title: string; blocks: ReportBlock[] };

export interface ReportSection {
  id: string;
  ey: string;
  label: string;
  subs: { id: string; label: string }[];
  blocks: ReportBlock[];
}

export interface Report {
  meta: { id: string; level: string; time: string; status: string; dot: "red" | "amber" | "green"; agent: string };
  summary: { rootcause: string; impact: string; confidence: string };
  sections: ReportSection[];
}

/** HTML 报告（真实路径：Baize + report_visualization 产出，已脱敏，内嵌展示）。 */
export interface HtmlReport {
  kind: "html";
  meta: { id: string; level: string; time: string; status: string; agent: string };
  html: string;
}

/** GET /api/tasks/:id/report 返回：结构化（mock）或 HTML（真实路径），按 kind 分支渲染。 */
export type ReportPayload = ({ kind?: "structured" } & Report) | HtmlReport;

// ---------- 已知问题对话查询（QA）模块（与 server/src/types.ts 对齐） ----------

export type QaRole = "user" | "assistant";
export type QaMessageStatus = "generating" | "done" | "aborted" | "failed";
export type QaFeedback = "useful" | "inaccurate";
export type CitationType = "doc" | "inc" | "skill" | "kb";

export interface RetrievalLevels {
  low: string[];
  high: string[];
}
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
  rel: number;
}
export interface GraphNode {
  id: string;
  x: number;
  y: number;
  t: "core" | "ent";
}
export interface GraphEdge {
  a: string;
  b: string;
  l: string;
}
export interface GraphSubview {
  nodes: GraphNode[];
  edges: GraphEdge[];
}

export interface QaSession {
  id: string;
  title: string;
  kbId: string | null;
  createdAt: number;
  updatedAt: number;
}
export interface QaMessage {
  id: string;
  sessionId: string;
  role: QaRole;
  status: QaMessageStatus | null;
  text: string;
  retrieval: RetrievalLevels | null;
  citations: Citation[] | null;
  graph: GraphSubview | null;
  followups: string[] | null;
  feedback: QaFeedback | null;
  createdAt: number;
}

export type StreamEvent =
  | { type: "snapshot"; status: TaskStatus; progress: number; stage: string | null; logs: { time: string; text: string }[] }
  | { type: "progress"; status: TaskStatus; progress: number; stage: string | null }
  | { type: "log"; time: string; text: string }
  | { type: "done"; status: TaskStatus };

/** QA SSE 事件（独立联合，避免与 task StreamEvent 混淆）。 */
export type QaStreamEvent =
  | { type: "qa_snapshot"; messages: QaMessage[] }
  | { type: "qa_token"; messageId: string; text: string }
  | { type: "qa_trace_start"; messageId: string }
  | { type: "qa_trace"; messageId: string; retrieval?: RetrievalLevels; sourceCount: number; degraded?: boolean; error?: string }
  | { type: "qa_evidence"; messageId: string; citations: Citation[]; graph?: GraphSubview | null; followups?: string[] }
  | { type: "qa_done"; messageId: string; status: QaMessageStatus }
  | { type: "qa_error"; messageId?: string; message: string };
