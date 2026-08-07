import { config } from "./config.js";
import * as repo from "./repositories.js";
import * as runner from "./runner.js";
import { publish } from "./streamHub.js";

/**
 * 调度器 / 队列（对应 02 §2.2.2 / BC-005 / NFR-005）。
 * 全局 FIFO 队列 + 并发上限；超额任务停留 queued，前序释放后自动放行。
 */

const queue: string[] = [];
let runningCount = 0;

export function enqueue(taskId: string): void {
  queue.push(taskId);
  pump();
}

function pump(): void {
  while (runningCount < config.scheduler.maxConcurrent && queue.length > 0) {
    const taskId = queue.shift()!;
    runningCount++;
    // run() 永不向调度循环抛出；终态在 runner 内部落库
    void runner
      .run(taskId)
      .catch(() => {
        /* runner 已处理失败落库 */
      })
      .finally(() => {
        runningCount--;
        pump();
      });
  }
}

/** 取消：运行中委派 runner 终止；排队中直接出队置 canceled。 */
export async function cancel(taskId: string): Promise<void> {
  if (runner.isRunning(taskId)) {
    runner.cancel(taskId);
    return;
  }
  const idx = queue.indexOf(taskId);
  if (idx >= 0) {
    queue.splice(idx, 1);
    await repo.updateTaskStatus(taskId, { status: "canceled", currentStage: "已取消", failReason: "任务在排队中被取消。" });
    publish(taskId, { type: "done", status: "canceled" });
  }
}

/** 重试：复用原 taskId，新增一次执行，重新入队（BC-006）。 */
export async function retry(taskId: string): Promise<void> {
  await repo.updateTaskStatus(taskId, { status: "queued", progress: 0, currentStage: "排队中", failReason: null });
  enqueue(taskId);
}

export function stats(): { running: number; queued: number; maxConcurrent: number } {
  return { running: runningCount, queued: queue.length, maxConcurrent: config.scheduler.maxConcurrent };
}
