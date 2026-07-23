/**
 * QA 模块 · 事件流 → SSE 证据合成（纯函数，对应 02 §4）。
 *
 * 把 opencode 单向事件流确定性地合成为前端可消费的「流式 token + 检索 trace + 证据」。
 * **纯函数 / 无 IO / 无脱敏**（脱敏由 qaRunner 在 publish 前做），便于单测（03 T105）。
 *
 * 降级谱系（与 01 场景对齐）：
 *  - state.output 非 JSON（MCP 返回格式异常）→ 证据降级 degraded，正文不受影响（S-008）
 *  - output 合法但缺逐条引用/图谱 → 缺失项置空、不渲染，正文正常（S-009）
 *  - tool error / LightRAG 超时不可达 → qa_trace.degraded + error（S-007）
 *  - 空检索（sources 为空）→ 证据置空，由上层走兜底文案（S-006/FR-010）
 */

import { parseLightragOutput } from "./qa/index.js";
import type { OpencodeEventPayload } from "./qa/index.js";
import type { RetrievalLevels, Citation, GraphSubview } from "./types.js";

/** synthesizer 产出的事件（不含 messageId；由 qaRunner 绑定后转 StreamEvent）。 */
export type QaSynthEvent =
  | { type: "qa_token"; text: string }
  | { type: "qa_trace_start" }
  | { type: "qa_trace"; retrieval?: RetrievalLevels; sourceCount: number; degraded?: boolean; error?: string }
  | { type: "qa_evidence"; citations: Citation[]; graph?: GraphSubview | null; followups?: string[] };

/** 合成过程的累积状态；qaRunner 在终态据此落库 assistant 快照。 */
export interface QaSynthState {
  text: string;
  toolStarted: boolean;
  retrieval: RetrievalLevels | null;
  citations: Citation[] | null;
  graph: GraphSubview | null;
  followups: string[] | null;
  degraded: boolean;
  error: string | null;
}

export function initQaSynthState(): QaSynthState {
  return {
    text: "",
    toolStarted: false,
    retrieval: null,
    citations: null,
    graph: null,
    followups: null,
    degraded: false,
    error: null,
  };
}

function isLightragTool(part: NonNullable<OpencodeEventPayload["properties"]>["part"]): boolean {
  const name = part?.tool || part?.name || "";
  return part?.type === "tool" && name.startsWith("lightrag");
}

/**
 * 单事件归约：输入当前状态 + 一个 opencode 事件，返回新状态 + 待发的 synth 事件。
 * O(1)；整条流 O(事件数)，内存仅累积当前消息文本（02 §4 复杂度分析）。
 */
export function reduceQaEvent(state: QaSynthState, ev: OpencodeEventPayload): { state: QaSynthState; emits: QaSynthEvent[] } {
  const props = ev.properties ?? {};

  switch (ev.type) {
    case "message.part.delta": {
      if (props.field !== "text") return { state, emits: [] };
      const delta = typeof props.delta === "string" ? props.delta : "";
      if (!delta) return { state, emits: [] };
      return { state: { ...state, text: state.text + delta }, emits: [{ type: "qa_token", text: delta }] };
    }

    case "message.part.updated": {
      const part = props.part;
      if (!isLightragTool(part)) return { state, emits: [] };
      const status = part?.state?.status;

      if (status === "running") {
        return { state: { ...state, toolStarted: true }, emits: [{ type: "qa_trace_start" }] };
      }

      if (status === "completed") {
        const meta = parseLightragOutput(part?.state?.output);
        if (meta === null) {
          // S-008：output 非 JSON / 非对象 → 证据降级，正文继续
          return {
            state: { ...state, degraded: true },
            emits: [{ type: "qa_trace", sourceCount: 0, degraded: true }],
          };
        }
        const next: QaSynthState = {
          ...state,
          retrieval: meta.retrieval,
          citations: meta.sources,
          graph: meta.graph ?? null,
          followups: meta.followups ?? [],
        };
        return {
          state: next,
          emits: [
            { type: "qa_trace", retrieval: meta.retrieval, sourceCount: meta.sources.length },
            { type: "qa_evidence", citations: meta.sources, graph: meta.graph ?? null, followups: meta.followups ?? [] },
          ],
        };
      }

      if (status === "error") {
        // S-007：tool error / LightRAG 不可达 → 降级提示，正文走兜底
        const error = part?.state?.error || "知识检索服务暂不可用";
        return {
          state: { ...state, degraded: true, error },
          emits: [{ type: "qa_trace", sourceCount: 0, degraded: true, error }],
        };
      }

      return { state, emits: [] };
    }

    // session.idle 等：完成判定/收敛由 qaRunner 负责，synthesizer 不发事件
    default:
      return { state, emits: [] };
  }
}
