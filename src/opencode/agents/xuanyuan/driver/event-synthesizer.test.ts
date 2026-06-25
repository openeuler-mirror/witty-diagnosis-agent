import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  initTaskSynthState,
  reduceTaskEvent,
  flushTaskSynth,
  type TaskSynthState,
} from "./event-synthesizer.js";
import type { OpencodeEventPayload, TaskDriverEvent } from "./types.js";

function delta(text: string): OpencodeEventPayload {
  return { type: "message.part.delta", properties: { field: "text", delta: text } };
}
function tool(tool: string, status: string, extra: Record<string, unknown> = {}): OpencodeEventPayload {
  return { type: "message.part.updated", properties: { part: { type: "tool", tool, state: { status, ...extra } } } };
}
function runAll(events: OpencodeEventPayload[]): { state: TaskSynthState; emits: TaskDriverEvent[] } {
  let state = initTaskSynthState();
  const emits: TaskDriverEvent[] = [];
  for (const ev of events) {
    const r = reduceTaskEvent(state, ev);
    state = r.state;
    emits.push(...r.emits);
  }
  emits.push(...flushTaskSynth(state));
  return { state, emits };
}

describe("task event synthesizer", () => {
  it("buffers text deltas into per-line logs", () => {
    const { emits } = runAll([delta("第一行"), delta("继续\n第二行"), delta("结尾")]);
    const logs = emits.filter((e) => e.type === "log").map((e) => (e as { text: string }).text);
    // 「第一行继续」遇换行落出；「第二行结尾」无换行，在 flush 时落出
    assert.deepEqual(logs, ["第一行继续", "第二行结尾"]);
  });

  it("advances stages forward-only from narration keywords", () => {
    const { emits } = runAll([
      delta("首先调用 Fuxi 构建诊断计划\n"),
      delta("调用 Dayu 编排，Kuafu 并行执行\n"),
      delta("Baize 根因分析中\n"),
      delta("调用 report_visualization 渲染报告\n"),
    ]);
    const stages = emits.filter((e) => e.type === "stage").map((e) => (e as { stage: string }).stage);
    assert.deepEqual(stages, ["数据采集"]);
  });

  it("never regresses stage when keywords arrive out of order", () => {
    const { emits } = runAll([
      delta("Baize 根因分析\n"), // 跳到 故障定位
      delta("Fuxi 计划\n"), // 不应回退
    ]);
    const stages = emits.filter((e) => e.type === "stage").map((e) => (e as { stage: string }).stage);
    assert.deepEqual(stages, ["数据采集"]);
  });

  it("maps tool running/completed to flow logs and report_visualization to 生成报告", () => {
    const { emits, state } = runAll([
      tool("task", "running", { input: { subagent_type: "fuxi-sub" } }),
      tool("task", "completed", { output: "plan written" }),
      tool("report_visualization", "running"),
    ]);
    const logs = emits.filter((e) => e.type === "log").map((e) => (e as { text: string }).text);
    assert.ok(logs.some((l) => l.includes("子代理 fuxi-sub")));
    assert.ok(logs.some((l) => l.includes("✓ task 完成")));
    const stages = emits.filter((e) => e.type === "stage").map((e) => (e as { stage: string }).stage);
    assert.ok(stages.includes("数据采集")); // fuxi-sub
    assert.ok(stages.includes("生成报告")); // report_visualization
    void state;
  });

  it("captures report path from markers across the stream", () => {
    const { state } = runAll([
      delta("已完成，RCA报告路径："),
      delta("/home/u/.witty-diagnosis-agent/baize/reports/x_report.html 请查收"),
    ]);
    assert.equal(state.reportPath, "/home/u/.witty-diagnosis-agent/baize/reports/x_report.html");
  });

  it("captures report path with 报告已写入 marker", () => {
    const { state } = runAll([delta("报告已写入：/tmp/report.html\n")]);
    assert.equal(state.reportPath, "/tmp/report.html");
  });
});
