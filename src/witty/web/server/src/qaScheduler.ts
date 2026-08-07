/**
 * QA 模块调度器（对应 02 §2.2.1 / 03 T106）。
 * 与诊断 scheduler.ts 相互独立、互不挤占（NFR-003）：
 *  - 全局 FIFO 队列 + 并发上限 config.conversation.maxConcurrent
 *  - **单会话 single-flight**：同一 conversationId 同时刻仅一个进行中/排队中的提问
 *  - 锁在「终态落库 / abort 完成」后于 finally 释放，确保 stop→立即重发不被 409 误拒（§2.2.1）
 */

import { config } from "./config.js";

export interface QaJob {
  conversationId: string;
  /** 实际执行一次问答；收到 signal 用于停止/超时中止。永不向调度循环抛出。 */
  run: (signal: AbortSignal) => Promise<void>;
}

interface Entry {
  job: QaJob;
  controller: AbortController;
  state: "queued" | "running";
}

const entries = new Map<string, Entry>();
const queue: string[] = [];
let runningCount = 0;

/** 该会话当前是否已有进行中/排队中的提问。 */
export function isActive(conversationId: string): boolean {
  return entries.has(conversationId);
}

/**
 * 入队一次提问。同会话已占用 → 返回 false（single-flight，路由层据此返 409）。
 */
export function enqueue(job: QaJob): boolean {
  if (entries.has(job.conversationId)) return false;
  entries.set(job.conversationId, { job, controller: new AbortController(), state: "queued" });
  queue.push(job.conversationId);
  pump();
  return true;
}

function pump(): void {
  while (runningCount < config.conversation.maxConcurrent && queue.length > 0) {
    const cid = queue.shift()!;
    const entry = entries.get(cid);
    if (!entry) continue; // 排队中被 abort 出队
    entry.state = "running";
    runningCount++;
    void entry.job
      .run(entry.controller.signal)
      .catch(() => {
        /* runner 内部已处理失败落库，不向调度循环抛出 */
      })
      .finally(() => {
        runningCount--;
        entries.delete(cid); // 释放 single-flight 锁
        pump();
      });
  }
}

/**
 * 停止生成：abort 活跃任务（runner 会标记中断并保留已生成）；排队中则直接出队。
 * 返回是否命中一个活跃会话。
 */
export function abort(conversationId: string): boolean {
  const entry = entries.get(conversationId);
  if (!entry) return false;
  entry.controller.abort();
  if (entry.state === "queued") {
    const idx = queue.indexOf(conversationId);
    if (idx >= 0) queue.splice(idx, 1);
    entries.delete(conversationId);
  }
  return true;
}

export function stats(): { running: number; queued: number; maxConcurrent: number } {
  return { running: runningCount, queued: queue.length, maxConcurrent: config.conversation.maxConcurrent };
}
