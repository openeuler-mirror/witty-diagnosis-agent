/**
 * QA 模块 · 一次问答的端到端编排（对应 02 §2.2.1 / 03 T106）。
 *
 * 驱动（mock/真实 opencode）产出 opencode 同构事件流 → qaEventSynthesizer 合成
 * → desensitizeWith 脱敏 → streamHub.publish（按 conversationId）→ 终态落库 assistant 快照。
 *
 * 本文件是 web 层 **首个真实问答编排**；驱动可替换（见 agents/taiyi/README.md），
 * 本层逻辑（合成/脱敏/落库/终态收敛）与驱动实现无关。
 */

import { config } from "./config.js";
import * as repo from "./repositories.js";
import { publish } from "./streamHub.js";
import { desensitize, desensitizeWith } from "./desensitize.js";
import { initQaSynthState, reduceQaEvent, type QaSynthEvent, type QaSynthState } from "./qaEventSynthesizer.js";
import { createQaDriver, type QaDriver } from "../../../agents/taiyi/index.js";
import type { StreamEvent, QaMessageStatus, Citation, RetrievalLevels, GraphSubview } from "./types.js";

let _driver: QaDriver | null = null;
function driver(): QaDriver {
  if (_driver) return _driver;
  _driver = createQaDriver({
    lightrag: {
      mock: config.lightrag.mock,
      endpoint: config.lightrag.endpoint,
      apiKey: config.lightrag.apiKey,
      apiKeyHeader: config.lightrag.apiKeyHeader,
      timeoutMs: config.lightrag.timeoutMs,
      defaultMode: config.lightrag.queryMode,
      responseType: config.lightrag.responseType,
      includeChunkContent: config.lightrag.includeChunkContent,
    },
  });
  return _driver;
}

export interface QaRunInput {
  /** = qa_sessions.id，同时作为 SSE 订阅命名空间。 */
  conversationId: string;
  /** 绑定的 opencode sessionId（可空，首轮新建）。 */
  ocSessionId: string | null;
  question: string;
  /** 路由层预插入的 assistant 占位消息（status=generating）。 */
  assistantMessageId: string;
}

// ---------- 脱敏（publish 与落库前；02 §2.2.1 / FR-013） ----------

function deRetrieval(r: RetrievalLevels): RetrievalLevels {
  return { low: r.low.map(desensitize), high: r.high.map(desensitize) };
}
function deCitations(cs: Citation[]): Citation[] {
  return cs.map((c) => ({
    ...c,
    title: desensitize(c.title),
    origin: desensitize(c.origin),
    excerpt: desensitize(c.excerpt),
    entities: c.entities.map(desensitize),
    relations: c.relations.map(desensitize),
  }));
}
function deGraph(g: GraphSubview | null | undefined): GraphSubview | null {
  if (!g) return null;
  return {
    nodes: g.nodes.map((n) => ({ ...n, id: desensitize(n.id) })),
    edges: g.edges.map((e) => ({ a: desensitize(e.a), b: desensitize(e.b), l: desensitize(e.l) })),
  };
}

/** 把 synth 事件脱敏并绑定 messageId → StreamEvent。 */
function toStreamEvent(emit: QaSynthEvent, messageId: string): StreamEvent {
  switch (emit.type) {
    case "qa_token":
      return { type: "qa_token", messageId, text: desensitize(emit.text) };
    case "qa_trace_start":
      return { type: "qa_trace_start", messageId };
    case "qa_trace":
      return {
        type: "qa_trace",
        messageId,
        retrieval: emit.retrieval ? deRetrieval(emit.retrieval) : undefined,
        sourceCount: emit.sourceCount,
        degraded: emit.degraded,
        error: emit.error ? desensitize(emit.error) : undefined,
      };
    case "qa_evidence":
      return {
        type: "qa_evidence",
        messageId,
        citations: deCitations(emit.citations),
        graph: deGraph(emit.graph),
        followups: emit.followups?.map(desensitize),
      };
  }
}

/**
 * 调度器放行后执行。Promise 在进入终态时 resolve；永不向调度循环抛出。
 */
export async function run(input: QaRunInput, schedulerSignal: AbortSignal): Promise<void> {
  const { conversationId, assistantMessageId, question } = input;

  // 内部信号：合并「用户停止」与「会话超时」（NFR-001/NFR-003）
  const ac = new AbortController();
  let abortReason: "stop" | "timeout" | null = null;
  const onStop = () => {
    abortReason = "stop";
    ac.abort();
  };
  if (schedulerSignal.aborted) onStop();
  else schedulerSignal.addEventListener("abort", onStop, { once: true });
  const timer = setTimeout(() => {
    abortReason = "timeout";
    ac.abort();
  }, config.conversation.timeoutMs);

  let state: QaSynthState = initQaSynthState();

  try {
    // 续跑/新建 opencode 会话；首轮把 ocSessionId 落库（多轮上下文，FR-005）
    const oc = await driver().ensureSession(input.ocSessionId ?? undefined);
    if (oc !== input.ocSessionId) await repo.touchQaSession(conversationId, { ocSessionId: oc });

    for await (const ev of driver().run({ question, sessionId: oc, signal: ac.signal })) {
      const r = reduceQaEvent(state, ev);
      state = r.state;
      for (const emit of r.emits) publish(conversationId, toStreamEvent(emit, assistantMessageId));
    }

    const status: QaMessageStatus = abortReason === "timeout" ? "failed" : abortReason === "stop" ? "aborted" : "done";
    await finalize(input, state, status, abortReason === "timeout" ? "生成超时，请重试。" : undefined);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    publish(conversationId, { type: "qa_error", messageId: assistantMessageId, message: desensitize(message) });
    await finalize(input, state, "failed", `执行异常：${message}`);
  } finally {
    clearTimeout(timer);
    schedulerSignal.removeEventListener("abort", onStop);
  }
}

/** 终态：脱敏后落库 assistant 快照并推送 qa_done。 */
async function finalize(input: QaRunInput, state: QaSynthState, status: QaMessageStatus, fallbackNote?: string): Promise<void> {
  const text = desensitizeWith(state.text || fallbackNote || "", []);
  await repo.updateQaMessage(input.assistantMessageId, {
    status,
    text,
    retrieval: state.retrieval ? deRetrieval(state.retrieval) : null,
    citations: state.citations ? deCitations(state.citations) : null,
    graph: deGraph(state.graph),
    followups: state.followups ?? null,
  });
  await repo.touchQaSession(input.conversationId);
  publish(input.conversationId, { type: "qa_done", messageId: input.assistantMessageId, status });
}
