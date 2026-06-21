import type { TaskStatus } from "./types";

const STATUS_MAP: Record<TaskStatus, { cls: string; text: string }> = {
  succeeded: { cls: "ok", text: "已完成" },
  running: { cls: "run", text: "运行中" },
  failed: { cls: "fail", text: "失败" },
  canceled: { cls: "fail", text: "已取消" },
  queued: { cls: "queue", text: "排队中" },
};

export function Pill({ status }: { status: TaskStatus }) {
  const m = STATUS_MAP[status] ?? STATUS_MAP.queued;
  return <span className={`pill ${m.cls}`}>{m.text}</span>;
}

export function fmtTime(ts: number): string {
  const d = new Date(ts);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

export function fmtSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}
