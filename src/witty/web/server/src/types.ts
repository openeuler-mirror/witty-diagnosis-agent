/** 后端领域类型 + 与前端共享的 API DTO（与 02 §5.1 / §6.1 对齐）。 */

import type { Citation, RetrievalLevels, GraphSubview } from "./qa/index.js";
export type { Citation, RetrievalLevels, GraphSubview } from "./qa/index.js";

export type TaskMode = "online" | "offline";
export type TaskStatus = "queued" | "running" | "succeeded" | "failed" | "canceled";

/** 进度阶段标签（与前端 stepper 一致）。 */
export const STAGES = ["排队中", "计划构建", "数据采集", "根因分析", "报告生成", "完成"] as const;
export type Stage = (typeof STAGES)[number];

export interface OnlineTargetDTO {
  hostIp: string;
  sshUser: string;
  sshPort: number;
}

export interface OfflineFileDTO {
  id: string;
  filename: string;
  size: number;
}

/** 任务对外视图（已脱敏；不含密码）。 */
export interface TaskDTO {
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
  target?: OnlineTargetDTO;
  files?: OfflineFileDTO[];
  rating?: number;
  hasReport: boolean;
}

export interface CreateTaskInput {
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
  logPath?: string; // 服务器端日志路径（文件或目录），由后端就地读取
}

// ---------- 结构化报告（RCA，与原型 report 结构一致） ----------

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

export interface ReportDTO {
  meta: {
    id: string;
    level: string;
    time: string;
    status: string;
    dot: "red" | "amber" | "green";
    agent: string;
  };
  summary: { rootcause: string; impact: string; confidence: string };
  sections: ReportSection[];
}

/** HTML 报告（真实路径：Baize + report_visualization 产出，已脱敏，前端内嵌展示）。 */
export interface HtmlReportDTO {
  kind: "html";
  meta: { id: string; level: string; time: string; status: string; agent: string };
  html: string;
}

/**
 * 报告对外载荷：结构化（mock）或 HTML（真实路径）。
 * GET /api/tasks/:id/report 返回二者之一；前端按 kind 分支渲染。
 */
export type ReportPayload = ({ kind?: "structured" } & ReportDTO) | HtmlReportDTO;

// ---------- 已知问题对话查询（QA）模块（02 §5.1 / §6.1） ----------

export type QaRole = "user" | "assistant";
export type QaMessageStatus = "generating" | "done" | "aborted" | "failed";
export type QaFeedback = "useful" | "inaccurate";

/** 会话对外视图（按 owner 隔离）。 */
export interface QaSessionDTO {
  id: string;
  title: string;
  kbId: string | null;
  createdAt: number;
  updatedAt: number;
}

/** 消息对外视图（已脱敏；assistant 含 trace/引用/图谱快照）。 */
export interface QaMessageDTO {
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

// ---------- SSE 事件 ----------

export type StreamEvent =
  | { type: "snapshot"; status: TaskStatus; progress: number; stage: string | null; logs: { time: string; text: string }[] }
  | { type: "progress"; status: TaskStatus; progress: number; stage: string | null }
  | { type: "log"; time: string; text: string }
  | { type: "done"; status: TaskStatus }
  // QA 模块事件（按 conversationId 订阅；与上面 task 事件成员互不冲突）
  | { type: "qa_snapshot"; messages: QaMessageDTO[] }
  | { type: "qa_token"; messageId: string; text: string }
  | { type: "qa_trace_start"; messageId: string }
  | { type: "qa_trace"; messageId: string; retrieval?: RetrievalLevels; sourceCount: number; degraded?: boolean; error?: string }
  | { type: "qa_evidence"; messageId: string; citations: Citation[]; graph?: GraphSubview | null; followups?: string[] }
  | { type: "qa_done"; messageId: string; status: QaMessageStatus }
  | { type: "qa_error"; messageId?: string; message: string };
