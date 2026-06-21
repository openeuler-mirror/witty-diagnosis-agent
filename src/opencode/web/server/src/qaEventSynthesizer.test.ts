/**
 * qaEventSynthesizer 单测（03 T105）。覆盖 §4 正常路径 + 5 类降级。
 * 运行：npm test（node --import tsx --test）。
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { initQaSynthState, reduceQaEvent, type QaSynthEvent, type QaSynthState } from "./qaEventSynthesizer.js";
import type { OpencodeEventPayload } from "../../../agents/taiyi/index.js";

function drive(events: OpencodeEventPayload[]): { state: QaSynthState; emits: QaSynthEvent[] } {
  let state = initQaSynthState();
  const emits: QaSynthEvent[] = [];
  for (const ev of events) {
    const r = reduceQaEvent(state, ev);
    state = r.state;
    emits.push(...r.emits);
  }
  return { state, emits };
}

const toolRunning: OpencodeEventPayload = {
  type: "message.part.updated",
  properties: { part: { type: "tool", tool: "lightrag_query", state: { status: "running" } } },
};

function toolCompleted(output: string): OpencodeEventPayload {
  return { type: "message.part.updated", properties: { part: { type: "tool", tool: "lightrag_query", state: { status: "completed", output } } } };
}

function textDelta(delta: string): OpencodeEventPayload {
  return { type: "message.part.delta", properties: { field: "text", delta } };
}

const FULL_OUTPUT = JSON.stringify({
  answer_context: "根因是 firewalld reload 清空 DOCKER 链[1]。",
  retrieval: { low: ["firewalld", "DOCKER 链"], high: ["容器网络中断"] },
  sources: [{ id: 1, type: "doc", badge: "官方文档", title: "容器网络", origin: "docs", url: "u", excerpt: "e", entities: ["firewalld"], relations: ["reload→重建"], rel: 96 }],
  graph: { nodes: [{ id: "firewalld", x: 1, y: 2, t: "ent" }], edges: [{ a: "firewalld", b: "x", l: "r" }] },
  followups: ["如何避免冲突？"],
});

test("正常路径：trace_start → trace + evidence → token，累积正文", () => {
  const { state, emits } = drive([
    toolRunning,
    toolCompleted(FULL_OUTPUT),
    textDelta("根因是 "),
    textDelta("firewalld reload[1]。"),
    { type: "session.idle" },
  ]);

  assert.equal(emits[0].type, "qa_trace_start");
  const trace = emits.find((e) => e.type === "qa_trace");
  assert.ok(trace && trace.type === "qa_trace");
  assert.equal(trace.sourceCount, 1);
  assert.deepEqual(trace.retrieval, { low: ["firewalld", "DOCKER 链"], high: ["容器网络中断"] });
  assert.ok(!trace.degraded);

  const evidence = emits.find((e) => e.type === "qa_evidence");
  assert.ok(evidence && evidence.type === "qa_evidence");
  assert.equal(evidence.citations.length, 1);
  assert.ok(evidence.graph && evidence.graph.nodes.length === 1);
  assert.deepEqual(evidence.followups, ["如何避免冲突？"]);

  const tokens = emits.filter((e) => e.type === "qa_token");
  assert.equal(tokens.length, 2);
  assert.equal(state.text, "根因是 firewalld reload[1]。");
  assert.equal(state.citations?.length, 1);
});

test("S-008：output 非 JSON → 证据降级 degraded，正文不受影响", () => {
  const { state, emits } = drive([toolRunning, toolCompleted("这不是 JSON {"), textDelta("正文照常输出")]);
  const trace = emits.find((e) => e.type === "qa_trace");
  assert.ok(trace && trace.type === "qa_trace" && trace.degraded === true);
  assert.equal(trace.sourceCount, 0);
  assert.ok(!emits.some((e) => e.type === "qa_evidence"));
  assert.equal(state.degraded, true);
  assert.equal(state.text, "正文照常输出");
});

test("S-009：output 合法但缺图谱/缺引用 → 缺失项置空、不报错，正文正常", () => {
  const output = JSON.stringify({ answer_context: "a", retrieval: { low: ["x"], high: [] }, sources: [], followups: [] });
  const { state, emits } = drive([toolRunning, toolCompleted(output), textDelta("有答案缺佐证")]);
  const trace = emits.find((e) => e.type === "qa_trace");
  assert.ok(trace && trace.type === "qa_trace");
  assert.equal(trace.sourceCount, 0);
  assert.ok(!trace.degraded);
  const evidence = emits.find((e) => e.type === "qa_evidence");
  assert.ok(evidence && evidence.type === "qa_evidence");
  assert.equal(evidence.citations.length, 0);
  assert.equal(evidence.graph, null); // 无 nodes → 规范化为 undefined → null
  assert.equal(state.text, "有答案缺佐证");
});

test("S-006：空检索（sources 为空）→ 证据置空，仍可走兜底正文", () => {
  const output = JSON.stringify({ answer_context: "", retrieval: { low: [], high: [] }, sources: [] });
  const { emits } = drive([toolRunning, toolCompleted(output)]);
  const evidence = emits.find((e) => e.type === "qa_evidence");
  assert.ok(evidence && evidence.type === "qa_evidence" && evidence.citations.length === 0);
});

test("S-007：tool error → qa_trace.degraded + error，无 evidence", () => {
  const errEvent: OpencodeEventPayload = {
    type: "message.part.updated",
    properties: { part: { type: "tool", tool: "lightrag_query", state: { status: "error", error: "LightRAG 超时" } } },
  };
  const { state, emits } = drive([toolRunning, errEvent]);
  const trace = emits.find((e) => e.type === "qa_trace");
  assert.ok(trace && trace.type === "qa_trace" && trace.degraded === true);
  assert.equal(trace.error, "LightRAG 超时");
  assert.equal(state.error, "LightRAG 超时");
  assert.ok(!emits.some((e) => e.type === "qa_evidence"));
});

test("非 lightrag 工具与非 text 部件被忽略", () => {
  const other: OpencodeEventPayload = { type: "message.part.updated", properties: { part: { type: "tool", tool: "bash", state: { status: "completed", output: "{}" } } } };
  const nonText: OpencodeEventPayload = { type: "message.part.delta", properties: { field: "reasoning", delta: "思考" } };
  const { state, emits } = drive([other, nonText]);
  assert.equal(emits.length, 0);
  assert.equal(state.text, "");
});
