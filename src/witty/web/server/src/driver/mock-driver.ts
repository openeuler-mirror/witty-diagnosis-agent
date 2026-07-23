/**
 * 故障运维诊断 · mock 驱动（本期默认）。
 *
 * 不起 opencode / LLM，用确定性的阶段时序模拟 Xuanyuan 全链路（Fuxi→Dayu→Kuafu→Baize→报告），
 * 产出与真实驱动同构的任务域事件流（stage / log / report），跑通整条主链路。
 * 切换真实路径见 ./index.ts 与 ./opencode-driver.ts。
 */

import { buildMockReportHtml } from "./report-template.js";
import { STAGE_PROGRESS, type Stage, type TaskDriver, type TaskDriverEvent, type TaskDriverInput } from "./types.js";

export interface MockDriverConfig {
  /** 每个阶段之间的停顿（ms），用于演示流式进度。 */
  stepDelayMs?: number;
}

const ONLINE_SEQ: [Stage, string][] = [
  ["计划构建", "▶ 调用子代理 fuxi-sub 构建诊断计划…"],
  ["计划构建", "SSH 连接已建立，开始采集系统指标（dmesg / journalctl / 连接状态）"],
  ["数据采集", "▶ 调用 Dayu 编排任务，Kuafu 并行执行采集脚本"],
  ["数据采集", "解析 23,481 条日志，提取异常模式与指标关联"],
  ["根因分析", "▶ 调用 Baize 进行根因分析（RCA）"],
  ["根因分析", "关联指标与日志，定位疑似根因与受影响范围"],
  ["报告生成", "▶ 调用 report_visualization 渲染 HTML 报告"],
];

const OFFLINE_SEQ: [Stage, string][] = [
  ["计划构建", "▶ 调用子代理 fuxi-sub 构建诊断计划…"],
  ["计划构建", "解压并校验上传日志，登记离线日志来源"],
  ["数据采集", "▶ 调用 Dayu/Kuafu 解析日志时间线，识别异常区间"],
  ["数据采集", "匹配已知故障特征库"],
  ["根因分析", "▶ 调用 Baize 定位根因与受影响范围"],
  ["报告生成", "▶ 调用 report_visualization 生成诊断报告"],
];

function sleep(ms: number, signal: AbortSignal): Promise<void> {
  if (signal.aborted) return Promise.resolve();
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      signal.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(timer);
      resolve();
    };
    signal.addEventListener("abort", onAbort, { once: true });
  });
}

export function createMockDriver(cfg: MockDriverConfig = {}): TaskDriver {
  const stepDelayMs = cfg.stepDelayMs ?? 950;

  return {
    async *run(input: TaskDriverInput): AsyncGenerator<TaskDriverEvent> {
      const { signal } = input;
      const seq = input.mode === "online" ? ONLINE_SEQ : OFFLINE_SEQ;

      yield { type: "stage", stage: "排队中", progress: STAGE_PROGRESS["排队中"] };
      yield { type: "log", text: "任务已创建，进入执行队列" };
      yield { type: "log", text: "我将启动全链路智能运维诊断流程。" };

      let lastStage: Stage | null = null;
      for (const [stage, msg] of seq) {
        if (signal.aborted) return;
        if (stage !== lastStage) {
          yield { type: "stage", stage, progress: STAGE_PROGRESS[stage] };
          lastStage = stage;
        }
        yield { type: "log", text: msg };
        await sleep(stepDelayMs, signal);
      }
      if (signal.aborted) return;

      const reportNo = `RCA-${new Date().toISOString().slice(0, 10).replace(/-/g, "")}-${input.taskId.slice(0, 4)}`;
      const { html, faultLevel } = buildMockReportHtml(input, reportNo);
      yield { type: "report", html, reportNo, faultLevel };
      yield { type: "log", text: "诊断完成，报告已生成 ✓" };
    },
  };
}
