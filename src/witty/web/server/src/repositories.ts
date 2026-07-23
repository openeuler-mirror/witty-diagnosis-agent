import path from "node:path";
import { v4 as uuid } from "uuid";
import { getDb } from "./db/knex.js";
import { config } from "./config.js";
import type {
  TaskDTO,
  TaskMode,
  TaskStatus,
  OnlineTargetDTO,
  OfflineFileDTO,
  ReportDTO,
  ReportPayload,
  HtmlReportDTO,
  QaSessionDTO,
  QaMessageDTO,
  QaRole,
  QaMessageStatus,
  QaFeedback,
  Citation,
  RetrievalLevels,
  GraphSubview,
} from "./types.js";

/**
 * 数据访问层（Repository，对应 02 §2.1.2「数据访问层」）。
 * 业务代码只调用这里的方法，不出现具体方言 SQL；所有接口为 async。
 */

function now(): number {
  return Date.now();
}

// ---------- Users ----------

export async function ensureUser(externalSubject: string, displayName: string): Promise<string> {
  const db = getDb();
  const existing = await db("users").where({ external_subject: externalSubject }).first();
  if (existing) return existing.id as string;
  const id = uuid();
  await db("users").insert({
    id,
    external_subject: externalSubject,
    display_name: displayName,
    created_at: now(),
  });
  return id;
}

// ---------- Uploads ----------

export async function createUpload(filename: string, storedPath: string, size: number): Promise<OfflineFileDTO> {
  const db = getDb();
  const id = uuid();
  await db("offline_uploads").insert({
    id,
    task_id: null,
    filename,
    stored_path: storedPath,
    size,
    uploaded_at: now(),
  });
  return { id, filename, size };
}

/** 服务器端日志路径作为离线来源：不复制文件，仅登记路径，后端就地读取。 */
export async function addServerPathSource(taskId: string, logPath: string): Promise<void> {
  const db = getDb();
  await db("offline_uploads").insert({
    id: uuid(),
    task_id: taskId,
    filename: path.basename(logPath.replace(/\/+$/, "")) || logPath,
    stored_path: logPath,
    size: 0,
    uploaded_at: now(),
  });
}

export async function attachUploadsToTask(taskId: string, uploadIds: string[]): Promise<void> {
  const db = getDb();
  if (uploadIds.length === 0) return;
  await db("offline_uploads").whereIn("id", uploadIds).update({ task_id: taskId });
}

export async function listUploads(taskId: string): Promise<OfflineFileDTO[]> {
  const db = getDb();
  const rows = await db("offline_uploads").where({ task_id: taskId }).orderBy("uploaded_at", "asc");
  return rows.map((r) => ({ id: r.id, filename: r.filename, size: Number(r.size) }));
}

/** 离线诊断的日志来源绝对路径（上传落盘路径或服务器路径），供驱动就地读取。 */
export async function listOfflineSourcePaths(taskId: string): Promise<string[]> {
  const db = getDb();
  const rows = await db("offline_uploads").where({ task_id: taskId }).orderBy("uploaded_at", "asc");
  return rows.map((r) => r.stored_path as string).filter(Boolean);
}

// ---------- Tasks ----------

export interface CreateTaskRow {
  ownerId: string;
  title: string;
  faultTime: string;
  mode: TaskMode;
  target?: OnlineTargetDTO;
}

export async function createTask(input: CreateTaskRow): Promise<string> {
  const db = getDb();
  const id = uuid();
  const ts = now();
  const expireAt = ts + config.task.retentionDays * 24 * 60 * 60 * 1000;
  await db("tasks").insert({
    id,
    owner_id: input.ownerId,
    title: input.title,
    fault_time: input.faultTime,
    mode: input.mode,
    status: "queued",
    progress: 0,
    current_stage: "排队中",
    created_at: ts,
    updated_at: ts,
    expire_at: expireAt,
  });
  if (input.mode === "online" && input.target) {
    await db("online_targets").insert({
      task_id: id,
      host_ip: input.target.hostIp,
      ssh_user: input.target.sshUser,
      ssh_port: input.target.sshPort,
    });
  }
  return id;
}

export async function updateTaskStatus(
  taskId: string,
  patch: { status?: TaskStatus; progress?: number; currentStage?: string | null; failReason?: string | null },
): Promise<void> {
  const db = getDb();
  const row: Record<string, unknown> = { updated_at: now() };
  if (patch.status !== undefined) row.status = patch.status;
  if (patch.progress !== undefined) row.progress = patch.progress;
  if (patch.currentStage !== undefined) row.current_stage = patch.currentStage;
  if (patch.failReason !== undefined) row.fail_reason = patch.failReason;
  await db("tasks").where({ id: taskId }).update(row);
}

async function toDTO(row: any): Promise<TaskDTO> {
  const db = getDb();
  const dto: TaskDTO = {
    id: row.id,
    ownerId: row.owner_id,
    title: row.title,
    faultTime: row.fault_time,
    mode: row.mode,
    status: row.status,
    progress: Number(row.progress),
    currentStage: row.current_stage ?? null,
    failReason: row.fail_reason ?? null,
    createdAt: Number(row.created_at),
    updatedAt: Number(row.updated_at),
    expireAt: Number(row.expire_at),
    hasReport: false,
  };
  if (row.mode === "online") {
    const t = await db("online_targets").where({ task_id: row.id }).first();
    if (t) dto.target = { hostIp: t.host_ip, sshUser: t.ssh_user, sshPort: Number(t.ssh_port) };
  } else {
    dto.files = await listUploads(row.id);
  }
  const rating = await db("ratings").where({ task_id: row.id }).first();
  if (rating) dto.rating = Number(rating.stars);
  const report = await db("reports").where({ task_id: row.id }).first();
  dto.hasReport = !!report;
  return dto;
}

/** 列表强制按 owner 隔离（BC-001 / NFR-003）。 */
export async function listTasks(ownerId: string, type: "all" | "online" | "offline"): Promise<TaskDTO[]> {
  const db = getDb();
  const q = db("tasks").where({ owner_id: ownerId });
  if (type !== "all") q.andWhere({ mode: type });
  const rows = await q.orderBy("created_at", "desc");
  return Promise.all(rows.map(toDTO));
}

/** 越权一致性：非 owner 一律视作不存在（返回 null → 路由层 404）。 */
export async function getTaskForOwner(taskId: string, ownerId: string): Promise<TaskDTO | null> {
  const db = getDb();
  const row = await db("tasks").where({ id: taskId, owner_id: ownerId }).first();
  if (!row) return null;
  return toDTO(row);
}

export async function getTaskRaw(taskId: string): Promise<any | null> {
  const db = getDb();
  return (await db("tasks").where({ id: taskId }).first()) ?? null;
}

export async function deleteTask(taskId: string): Promise<void> {
  const db = getDb();
  // 外键 onDelete CASCADE 负责连带清理子表（FR-010 / BC-007）
  await db("tasks").where({ id: taskId }).del();
}

// ---------- Executions & Logs ----------

export async function createExecution(taskId: string): Promise<string> {
  const db = getDb();
  const prev = await db("executions").where({ task_id: taskId }).count<{ c: number }[]>({ c: "*" });
  const attemptNo = Number(prev[0]?.c ?? 0) + 1;
  const id = uuid();
  await db("executions").insert({ id, task_id: taskId, attempt_no: attemptNo, started_at: now() });
  return id;
}

export async function endExecution(executionId: string, exitReason: string): Promise<void> {
  const db = getDb();
  await db("executions").where({ id: executionId }).update({ ended_at: now(), exit_reason: exitReason });
}

export async function latestExecution(taskId: string): Promise<string | null> {
  const db = getDb();
  const row = await db("executions").where({ task_id: taskId }).orderBy("attempt_no", "desc").first();
  return row?.id ?? null;
}

export async function appendLog(executionId: string, seq: number, text: string): Promise<void> {
  const db = getDb();
  await db("log_chunks").insert({ execution_id: executionId, seq, ts: now(), text });
}

export async function listLogs(taskId: string): Promise<{ time: string; text: string }[]> {
  const db = getDb();
  const exec = await latestExecution(taskId);
  if (!exec) return [];
  const rows = await db("log_chunks").where({ execution_id: exec }).orderBy("seq", "asc");
  return rows.map((r) => ({
    time: new Date(Number(r.ts)).toLocaleTimeString("zh-CN", { hour12: false }),
    text: r.text,
  }));
}

// ---------- Reports & Ratings ----------

export async function saveReport(taskId: string, report: ReportDTO): Promise<void> {
  const db = getDb();
  await db("reports")
    .insert({
      id: uuid(),
      task_id: taskId,
      report_no: report.meta.id,
      fault_level: report.meta.level,
      report_json: JSON.stringify({ kind: "structured", ...report }),
      created_at: now(),
    })
    .onConflict("task_id")
    .merge();
}

export interface SaveHtmlReportInput {
  reportNo: string;
  faultLevel: string;
  /** 已脱敏的报告 HTML（前端内嵌展示）。 */
  html: string;
  /** 原始产物路径（真实路径下 baize/reports/*.html；仅留痕，不对外）。 */
  htmlPath?: string;
  mdPath?: string;
  reportTime?: string;
}

/** 保存 HTML 报告（真实路径产物）。HTML 内容存入 report_json 的 {kind:"html"} 包裹，无需新增列。 */
export async function saveHtmlReport(taskId: string, input: SaveHtmlReportInput): Promise<void> {
  const db = getDb();
  const payload: HtmlReportDTO = {
    kind: "html",
    meta: {
      id: input.reportNo,
      level: input.faultLevel,
      time: input.reportTime || new Date(now()).toLocaleString("zh-CN", { hour12: false }),
      status: "诊断完成",
      agent: "Xuanyuan",
    },
    html: input.html,
  };
  await db("reports")
    .insert({
      id: uuid(),
      task_id: taskId,
      report_no: input.reportNo,
      fault_level: input.faultLevel,
      html_path: input.htmlPath ?? null,
      md_path: input.mdPath ?? null,
      report_json: JSON.stringify(payload),
      created_at: now(),
    })
    .onConflict("task_id")
    .merge();
}

export async function getReport(taskId: string): Promise<ReportPayload | null> {
  const db = getDb();
  const row = await db("reports").where({ task_id: taskId }).first();
  if (!row?.report_json) return null;
  const parsed = JSON.parse(row.report_json) as ReportPayload;
  // 兼容历史行（无 kind）：视为结构化报告
  if (!("kind" in parsed) || (parsed as { kind?: string }).kind === undefined) {
    return { kind: "structured", ...(parsed as ReportDTO) };
  }
  return parsed;
}

export async function upsertRating(taskId: string, stars: number, note?: string): Promise<void> {
  const db = getDb();
  await db("ratings")
    .insert({ task_id: taskId, stars, note: note ?? null, updated_at: now() })
    .onConflict("task_id")
    .merge();
}

// ---------- Retention cleanup ----------

export async function cleanupExpired(): Promise<number> {
  const db = getDb();
  const expired = await db("tasks").where("expire_at", "<", now()).select("id");
  for (const r of expired) await deleteTask(r.id);
  return expired.length;
}

/** 启动恢复：运行中任务在重启后无对应进程 → 置 failed 兜底（NFR-006）。 */
export async function failOrphanRunning(): Promise<number> {
  const db = getDb();
  const n = await db("tasks")
    .where({ status: "running" })
    .update({ status: "failed", fail_reason: "服务重启，运行中任务已中断，请重试。", updated_at: now() });
  return n;
}

// ============================================================================
// 已知问题对话查询（QA）模块（02 §5.1）。owner 隔离落 qa_sessions.owner_id；
// 越权一律视作不存在（返回 null → 路由层 404，不泄露存在性，BC-004）。
// ============================================================================

function parseJson<T>(v: unknown): T | null {
  if (typeof v !== "string" || v === "") return null;
  try {
    return JSON.parse(v) as T;
  } catch {
    return null;
  }
}

function toQaSessionDTO(row: any): QaSessionDTO {
  return {
    id: row.id,
    title: row.title,
    kbId: row.kb_id ?? null,
    createdAt: Number(row.created_at),
    updatedAt: Number(row.updated_at),
  };
}

function toQaMessageDTO(row: any): QaMessageDTO {
  return {
    id: row.id,
    sessionId: row.session_id,
    role: row.role as QaRole,
    status: (row.status ?? null) as QaMessageStatus | null,
    text: row.text ?? "",
    retrieval: parseJson<RetrievalLevels>(row.retrieval),
    citations: parseJson<Citation[]>(row.citations),
    graph: parseJson<GraphSubview>(row.graph),
    followups: parseJson<string[]>(row.followups),
    feedback: (row.feedback ?? null) as QaFeedback | null,
    createdAt: Number(row.created_at),
  };
}

export async function createQaSession(ownerId: string, title: string, kbId?: string | null): Promise<QaSessionDTO> {
  const db = getDb();
  const id = uuid();
  const ts = now();
  await db("qa_sessions").insert({
    id,
    owner_id: ownerId,
    title,
    oc_session_id: null,
    kb_id: kbId ?? null,
    created_at: ts,
    updated_at: ts,
  });
  return { id, title, kbId: kbId ?? null, createdAt: ts, updatedAt: ts };
}

export async function listQaSessions(ownerId: string): Promise<QaSessionDTO[]> {
  const db = getDb();
  const rows = await db("qa_sessions").where({ owner_id: ownerId }).orderBy("updated_at", "desc");
  return rows.map(toQaSessionDTO);
}

/** 越权一致性：非 owner 返回 null。 */
export async function getQaSessionForOwner(sessionId: string, ownerId: string): Promise<QaSessionDTO | null> {
  const db = getDb();
  const row = await db("qa_sessions").where({ id: sessionId, owner_id: ownerId }).first();
  return row ? toQaSessionDTO(row) : null;
}

/** 内部用：取原始行（含 oc_session_id），仍按 owner 隔离。 */
export async function getQaSessionRawForOwner(sessionId: string, ownerId: string): Promise<any | null> {
  const db = getDb();
  return (await db("qa_sessions").where({ id: sessionId, owner_id: ownerId }).first()) ?? null;
}

export async function touchQaSession(sessionId: string, patch?: { title?: string; ocSessionId?: string | null }): Promise<void> {
  const db = getDb();
  const row: Record<string, unknown> = { updated_at: now() };
  if (patch?.title !== undefined) row.title = patch.title;
  if (patch?.ocSessionId !== undefined) row.oc_session_id = patch.ocSessionId;
  await db("qa_sessions").where({ id: sessionId }).update(row);
}

export async function deleteQaSession(sessionId: string): Promise<void> {
  const db = getDb();
  // 外键 onDelete CASCADE 连带删除 qa_messages
  await db("qa_sessions").where({ id: sessionId }).del();
}

export interface AppendQaMessageInput {
  sessionId: string;
  role: QaRole;
  status?: QaMessageStatus | null;
  text?: string;
  retrieval?: RetrievalLevels | null;
  citations?: Citation[] | null;
  graph?: GraphSubview | null;
  followups?: string[] | null;
}

export async function appendQaMessage(input: AppendQaMessageInput): Promise<string> {
  const db = getDb();
  const id = uuid();
  await db("qa_messages").insert({
    id,
    session_id: input.sessionId,
    role: input.role,
    status: input.status ?? null,
    text: input.text ?? "",
    retrieval: input.retrieval ? JSON.stringify(input.retrieval) : null,
    citations: input.citations ? JSON.stringify(input.citations) : null,
    graph: input.graph ? JSON.stringify(input.graph) : null,
    followups: input.followups ? JSON.stringify(input.followups) : null,
    feedback: null,
    created_at: now(),
  });
  return id;
}

export interface UpdateQaMessagePatch {
  status?: QaMessageStatus;
  text?: string;
  retrieval?: RetrievalLevels | null;
  citations?: Citation[] | null;
  graph?: GraphSubview | null;
  followups?: string[] | null;
  feedback?: QaFeedback | null;
}

export async function updateQaMessage(messageId: string, patch: UpdateQaMessagePatch): Promise<void> {
  const db = getDb();
  const row: Record<string, unknown> = {};
  if (patch.status !== undefined) row.status = patch.status;
  if (patch.text !== undefined) row.text = patch.text;
  if (patch.retrieval !== undefined) row.retrieval = patch.retrieval ? JSON.stringify(patch.retrieval) : null;
  if (patch.citations !== undefined) row.citations = patch.citations ? JSON.stringify(patch.citations) : null;
  if (patch.graph !== undefined) row.graph = patch.graph ? JSON.stringify(patch.graph) : null;
  if (patch.followups !== undefined) row.followups = patch.followups ? JSON.stringify(patch.followups) : null;
  if (patch.feedback !== undefined) row.feedback = patch.feedback;
  if (Object.keys(row).length === 0) return;
  await db("qa_messages").where({ id: messageId }).update(row);
}

export async function listQaMessages(sessionId: string): Promise<QaMessageDTO[]> {
  const db = getDb();
  const rows = await db("qa_messages").where({ session_id: sessionId }).orderBy("created_at", "asc");
  return rows.map(toQaMessageDTO);
}

/**
 * 反馈落库（FR-008）：仅当消息属于该会话且为 assistant 时生效；返回是否命中（否则路由 404）。
 * 会话归属由路由层先经 getQaSessionForOwner 校验，这里再约束 message↔session 关系。
 */
export async function setQaFeedback(messageId: string, sessionId: string, feedback: QaFeedback): Promise<boolean> {
  const db = getDb();
  const n = await db("qa_messages").where({ id: messageId, session_id: sessionId, role: "assistant" }).update({ feedback });
  return n > 0;
}

/** 启动恢复：残留 generating 的 assistant 消息置 failed（NFR-002）。 */
export async function failOrphanQaGenerating(): Promise<number> {
  const db = getDb();
  return db("qa_messages")
    .where({ status: "generating" })
    .update({ status: "failed", text: "服务重启，生成已中断，请重试。" });
}
