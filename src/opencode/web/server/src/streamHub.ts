import type { StreamEvent } from "./types.js";

/**
 * 进度/日志实时通道（SSE）发布订阅中心（对应 02 §2.1.2 Streamer / FR-006）。
 * Runner 调 publish()，路由层把 HTTP reply 注册为 subscriber。
 * 仅推送已脱敏内容（脱敏在 Runner 侧持久化前完成）。
 */

type Subscriber = (event: StreamEvent) => void;

const subscribers = new Map<string, Set<Subscriber>>();

export function subscribe(taskId: string, fn: Subscriber): () => void {
  let set = subscribers.get(taskId);
  if (!set) {
    set = new Set();
    subscribers.set(taskId, set);
  }
  set.add(fn);
  return () => {
    set?.delete(fn);
    if (set && set.size === 0) subscribers.delete(taskId);
  };
}

export function publish(taskId: string, event: StreamEvent): void {
  const set = subscribers.get(taskId);
  if (!set) return;
  for (const fn of set) {
    try {
      fn(event);
    } catch {
      /* 单个订阅者异常不影响其他 */
    }
  }
}
