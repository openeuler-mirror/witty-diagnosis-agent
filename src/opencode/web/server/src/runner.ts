import fs from "node:fs";
import path from "node:path";
import * as repo from "./repositories.js";
import * as vault from "./vault.js";
import { config } from "./config.js";
import { publish } from "./streamHub.js";
import { desensitizeWith } from "./desensitize.js";
import { STAGES, type TaskStatus } from "./types.js";
import {
  createTaskDriver,
  type TaskDriver,
  type TaskDriverInput,
} from "../../../agents/xuanyuan/driver/index.js";

/**
 * Agent Runner（对应 02 §2.2.1 / §D-001 / §D-002）。
 *
 * 一次诊断的端到端编排：构造驱动输入（故障信息 + 在线凭据/离线日志路径 + 每任务 HOME）→
 * 驱动产出任务域事件流（stage/log/report）→ 脱敏 → 落库执行记录/日志/报告 → SSE 推送 →
 * 双终态判定（产出 report=成功，否则失败）；finally 擦除凭据保险箱与每任务 HOME。
 *
 * 驱动可替换（TASK_DRIVER=mock|opencode，见 agents/xuanyuan/driver）：
 *  - mock：确定性阶段时序模拟，无需模型/opencode。
 *  - opencode：真实路径，createOpencode + 重定向 HOME/XDG 隔离，驱动 xuanyuan 全链路。
 * 本层（脱敏/落库/终态收敛/SSE）与驱动实现无关。
 */

interface RunHandle {
  abort: AbortController;
  /** opencode server 关闭函数（由驱动在 createOpencode 后注册），用于取消时定点清理该任务进程。 */
  closeServer?: () => void;
}

const running = new Map<string, RunHandle>();

let _driver: Promise<TaskDriver> | null = null;
function driver(): Promise<TaskDriver> {
  if (!_driver) {
    _driver = createTaskDriver({
      driver: config.task.driver,
      opencode: {
        model: config.task.model,
        outputLanguage: config.task.outputLanguage,
        serverTimeoutMs: config.task.serverTimeoutMs,
        opencodeBin: config.task.opencodeBin,
      },
    });
  }
  return _driver;
}

function nowTime(): string {
  return new Date().toLocaleTimeString("zh-CN", { hour12: false });
}

/** 每任务专属 HOME（真实路径隔离根，BC-011/D-001）。 */
function taskHomeFor(taskId: string): string {
  return path.join(config.task.ocHomeBase, taskId);
}

/** 调度器调用：执行一次诊断，Promise 在任务进入终态时 resolve（永不向调度循环抛出）。 */
export async function run(taskId: string): Promise<void> {
  const task = await repo.getTaskRaw(taskId);
  if (!task) return;

  const abort = new AbortController();
  running.set(taskId, { abort });

  const executionId = await repo.createExecution(taskId);
  const cred = vault.reveal(taskId); // 在线任务密码（仅内存）；脱敏 + SSH 注入
  const secrets = cred ? [cred.sshPassword, cred.sshUser, cred.hostIp] : [];
  const taskHome = taskHomeFor(taskId);

  let seq = 1;
  const emitLog = async (text: string) => {
    const safe = desensitizeWith(text, secrets);
    await repo.appendLog(executionId, seq++, safe);
    publish(taskId, { type: "log", time: nowTime(), text: safe });
  };
  const setProgress = async (status: TaskStatus, progress: number, stage: string) => {
    await repo.updateTaskStatus(taskId, { status, progress, currentStage: stage });
    publish(taskId, { type: "progress", status, progress, stage });
  };

  // 任务级超时（NFR-005）：到点 abort，按取消/失败收敛
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    abort.abort();
  }, config.task.timeoutMs);

  let gotReport = false;

  try {
    await setProgress("running", 4, "排队中");
    await emitLog("任务已创建，进入执行队列");

    const input: TaskDriverInput = {
      taskId,
      title: task.title,
      faultTime: task.fault_time,
      mode: task.mode,
      taskHome,
      signal: abort.signal,
      ...(task.mode === "online" && cred
        ? { online: { hostIp: cred.hostIp, sshUser: cred.sshUser, sshPort: cred.sshPort, sshPassword: cred.sshPassword } }
        : {}),
      ...(task.mode === "offline" ? { offline: { logPaths: await repo.listOfflineSourcePaths(taskId) } } : {}),
      onServerReady: (close) => {
        const h = running.get(taskId);
        if (h) h.closeServer = close;
      },
    };

    const drv = await driver();
    for await (const ev of drv.run(input)) {
      if (abort.signal.aborted) break;
      if (ev.type === "stage") {
        await setProgress("running", ev.progress, ev.stage);
      } else if (ev.type === "log") {
        await emitLog(ev.text);
      } else if (ev.type === "report") {
        const safeHtml = desensitizeWith(ev.html, secrets);
        const reportNo = ev.reportNo || `RCA-${new Date().toISOString().slice(0, 10).replace(/-/g, "")}-${taskId.slice(0, 4)}`;
        await repo.saveHtmlReport(taskId, { reportNo, faultLevel: ev.faultLevel || "—", html: safeHtml });
        gotReport = true;
      }
    }

    if (abort.signal.aborted) throw new CancelError(timedOut ? "timeout" : "cancel");

    if (gotReport) {
      await setProgress("succeeded", 100, "完成");
      await repo.endExecution(executionId, "succeeded");
      publish(taskId, { type: "done", status: "succeeded" });
    } else {
      // 驱动结束但未产出报告 → 失败
      await repo.updateTaskStatus(taskId, { status: "failed", failReason: "诊断结束但未生成报告，请重试。" });
      await repo.endExecution(executionId, "failed");
      publish(taskId, { type: "done", status: "failed" });
    }
  } catch (err) {
    if (err instanceof CancelError && err.kind === "cancel") {
      await repo.updateTaskStatus(taskId, { status: "canceled", currentStage: "已取消", failReason: "任务已被用户取消。" });
      await repo.endExecution(executionId, "canceled");
      publish(taskId, { type: "done", status: "canceled" });
    } else if (err instanceof CancelError && err.kind === "timeout") {
      await repo.updateTaskStatus(taskId, { status: "failed", currentStage: "已超时", failReason: "诊断超时，已中止，请重试。" });
      await repo.endExecution(executionId, "failed");
      publish(taskId, { type: "done", status: "failed" });
    } else {
      const reason = err instanceof Error ? err.message : String(err);
      const safe = desensitizeWith(reason, secrets);
      await repo.updateTaskStatus(taskId, { status: "failed", failReason: `执行异常：${safe}` });
      await repo.endExecution(executionId, "failed");
      publish(taskId, { type: "done", status: "failed" });
    }
  } finally {
    clearTimeout(timer);
    // 仅成功时擦除凭据；取消、失败、超时都保留（重试时复用连接信息）
    if (gotReport) {
      vault.wipe(taskId);
    }
    // 真实路径：擦除每任务 HOME（连同会话存储/采集中间产物）
    if (config.task.driver === "opencode") wipeTaskHome(taskHome);
    running.delete(taskId);
  }
}

/** 取消运行中任务：定点关闭该任务的 opencode serve 进程 + 发 abort 信号。
 * 通过驱动注册的 closeServer 回调精确关闭目标进程，避免误杀其它并发任务的 serve。
 * 取消时先从 running map 删除，保证幂等性——后续同 taskId 的 cancel 调用直接跳过。 */
export function cancel(taskId: string): void {
  const handle = running.get(taskId);
  if (!handle) return;
  running.delete(taskId); // 立即删除，保证幂等
  // 优先通过驱动注册的 closeServer 定点关闭该任务进程（释放端口），再发 abort 信号
  try {
    handle.closeServer?.();
  } catch { /* ignore */ }
  handle.abort.abort();
}

export function isRunning(taskId: string): boolean {
  return running.has(taskId);
}

function wipeTaskHome(taskHome: string): void {
  // 安全护栏：仅擦除 ocHomeBase 下的目录，绝不越界
  const base = path.resolve(config.task.ocHomeBase);
  const target = path.resolve(taskHome);
  if (target === base || !target.startsWith(base + path.sep)) return;
  try {
    fs.rmSync(target, { recursive: true, force: true });
  } catch {
    /* 擦除失败不影响终态 */
  }
}

class CancelError extends Error {
  constructor(public kind: "cancel" | "timeout") {
    super(kind);
  }
}

export { STAGES };
