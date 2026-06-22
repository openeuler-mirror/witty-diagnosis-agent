import type {
  CreateTaskBody,
  OfflineFile,
  QaMessage,
  QaSession,
  QaStreamEvent,
  ReportPayload,
  SessionUser,
  StreamEvent,
  Task,
  TaskDetail,
  TaskStatus,
} from "./types";

/** 薄 API 客户端，封装 02 §6.1 的 REST + SSE 契约。同源调用（容器内 nginx 反代）。 */

async function req<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, {
    credentials: "include",
    headers: init?.body && !(init.body instanceof FormData) ? { "Content-Type": "application/json" } : undefined,
    ...init,
  });
  if (res.status === 204) return undefined as T;
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(res.status, (data as { error?: string }).error || `HTTP ${res.status}`);
  return data as T;
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

// ---- auth ----
export const login = (username: string, password: string) =>
  req<SessionUser>("/api/auth/login", { method: "POST", body: JSON.stringify({ username, password }) });
export const me = () => req<SessionUser>("/api/auth/me");
export const logout = () => req<{ ok: boolean }>("/api/auth/logout", { method: "POST" });

// ---- tasks ----
export const listTasks = (type: "all" | "online" | "offline" = "all") =>
  req<Task[]>(`/api/tasks?type=${type}`);
export const getTask = (id: string) => req<TaskDetail>(`/api/tasks/${id}`);
export const createTask = (body: CreateTaskBody) =>
  req<{ taskId: string; status: TaskStatus }>("/api/tasks", { method: "POST", body: JSON.stringify(body) });
export const connectivityTest = (body: { hostIp: string; sshUser: string; sshPassword: string; sshPort: number }) =>
  req<{ ok: boolean; reason?: string }>("/api/tasks/connectivity-test", { method: "POST", body: JSON.stringify(body) });
export const cancelTask = (id: string) => req<{ status: TaskStatus }>(`/api/tasks/${id}/cancel`, { method: "POST" });
export const retryTask = (id: string) => req<{ status: TaskStatus }>(`/api/tasks/${id}/retry`, { method: "POST" });
export const deleteTask = (id: string) => req<{ ok: boolean }>(`/api/tasks/${id}`, { method: "DELETE" });
export const getReport = (id: string) => req<ReportPayload>(`/api/tasks/${id}/report`);
export const rateTask = (id: string, stars: number, note?: string) =>
  req<{ stars: number }>(`/api/tasks/${id}/rating`, { method: "PUT", body: JSON.stringify({ stars, note }) });

// ---- uploads ----
export async function uploadLog(file: File): Promise<OfflineFile> {
  const fd = new FormData();
  fd.append("file", file);
  return req<OfflineFile>("/api/uploads", { method: "POST", body: fd });
}

// ---- SSE ----
export function streamTask(id: string, onEvent: (e: StreamEvent) => void): () => void {
  const es = new EventSource(`/api/tasks/${id}/stream`, { withCredentials: true });
  es.onmessage = (ev) => {
    try {
      onEvent(JSON.parse(ev.data));
    } catch {
      /* ignore malformed frame */
    }
  };
  es.onerror = () => {
    // EventSource 会自动重连；快照机制保证对齐
  };
  return () => es.close();
}

// ---- QA（已知问题对话查询） ----
export const qaCapabilities = () => req<{ qa: boolean }>("/api/capabilities");
export const listQaSessions = () => req<QaSession[]>("/api/qa/sessions");
export const createQaSession = (title?: string) =>
  req<{ id: string; createdAt: number }>("/api/qa/sessions", { method: "POST", body: JSON.stringify({ title }) });
export const getQaSession = (id: string) =>
  req<{ session: QaSession; messages: QaMessage[] }>(`/api/qa/sessions/${id}`);
export const deleteQaSession = (id: string) => req<{ ok: boolean }>(`/api/qa/sessions/${id}`, { method: "DELETE" });
export const postQaMessage = (id: string, text: string) =>
  req<{ userMessageId: string; assistantMessageId: string }>(`/api/qa/sessions/${id}/messages`, {
    method: "POST",
    body: JSON.stringify({ text }),
  });
export const stopQa = (id: string) => req<{ ok: boolean }>(`/api/qa/sessions/${id}/stop`, { method: "POST" });
export const putQaFeedback = (id: string, mid: string, feedback: "useful" | "inaccurate") =>
  req<{ ok: boolean }>(`/api/qa/sessions/${id}/messages/${mid}/feedback`, {
    method: "PUT",
    body: JSON.stringify({ feedback }),
  });

export function streamQa(id: string, onEvent: (e: QaStreamEvent) => void): () => void {
  const es = new EventSource(`/api/qa/sessions/${id}/stream`, { withCredentials: true });
  es.onmessage = (ev) => {
    try {
      onEvent(JSON.parse(ev.data));
    } catch {
      /* ignore malformed frame */
    }
  };
  es.onerror = () => {
    /* EventSource 自动重连；qa_snapshot 首帧对齐 */
  };
  return () => es.close();
}
