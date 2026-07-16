/**
 * 已知问题问答（QA）模块 · mock 驱动。
 *
 * 不起 opencode / LLM，直接调用 LightRAG（mock）客户端，把结果合成一条
 * **与 opencode 事件流同构** 的事件序列：
 *   tool(running) → tool(completed, output=JSON 字符串) → message.part.delta(text)* → session.idle
 *
 * 这样 web/server 的 qaEventSynthesizer / qaRunner 走的是与真实路径完全一致的消费逻辑，
 * 后续把驱动换成 opencode-driver 即可，HTTP/合成/落库层零改动（02 §2.2.1）。
 */

import { randomUUID } from "node:crypto";
import { createLightragClient, LightragUnavailableError, type LightragClientConfig } from "../lightrag/client.js";
import { LIGHTRAG_TOOL_NAME, type OpencodeEventPayload, type QaDriver, type QaDriverInput } from "./types.js";

export interface MockDriverConfig {
  lightrag: LightragClientConfig;
  /** 检索阶段模拟耗时（ms）。 */
  retrievalDelayMs?: number;
  /** 每个 token 之间的间隔（ms），用于演示流式。 */
  tokenIntervalMs?: number;
}

/** 可被 abort 提前唤醒的 sleep。abort 时 resolve（由调用方检查 signal 决定后续）。 */
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

/** 把答复文本切成小块，模拟 LLM 逐 token 流式（按标点/换行/定长混合切分）。 */
function chunkText(text: string): string[] {
  const chunks: string[] = [];
  let buf = "";
  for (const ch of text) {
    buf += ch;
    // 中文按 ~6 字、遇到标点或换行立即出块，贴近真实流式观感
    if (buf.length >= 6 || /[，。；、！？\n,.;!?]/.test(ch)) {
      chunks.push(buf);
      buf = "";
    }
  }
  if (buf) chunks.push(buf);
  return chunks;
}

export function createMockDriver(cfg: MockDriverConfig): QaDriver {
  const client = createLightragClient(cfg.lightrag);
  const retrievalDelayMs = cfg.retrievalDelayMs ?? 700;
  const tokenIntervalMs = cfg.tokenIntervalMs ?? 22;

  return {
    async ensureSession(sessionId?: string): Promise<{ sessionId: string; contextReset: boolean }> {
      return { sessionId: sessionId ?? `mock-${randomUUID()}`, contextReset: false };
    },
    async *run(input: QaDriverInput): AsyncGenerator<OpencodeEventPayload> {
      const { signal } = input;

      // 1) 检索工具开始（running）
      yield {
        type: "message.part.updated",
        properties: { part: { type: "tool", tool: LIGHTRAG_TOOL_NAME, state: { status: "running" } } },
      };

      await sleep(retrievalDelayMs, signal);
      if (signal.aborted) return;

      // 2) 调 LightRAG（mock/real）；不可达 → 工具 error（S-007/S-008 降级由 synthesizer 处理）
      let outputJson: string;
      let answer: string;
      try {
        const result = await client.query({
          question: input.question,
          mode: cfg.lightrag.defaultMode ?? "mix",
          sessionId: input.sessionId,
        });
        outputJson = JSON.stringify(result);
        answer = result.answer_context || "未在知识库找到充分依据，请补充更具体的报错或日志片段。";
      } catch (err) {
        const message = err instanceof LightragUnavailableError ? err.message : "知识检索服务暂不可用";
        yield {
          type: "message.part.updated",
          properties: { part: { type: "tool", tool: LIGHTRAG_TOOL_NAME, state: { status: "error", error: message } } },
        };
        // 降级正文
        for (const piece of chunkText("知识检索服务暂不可用，请稍后重试。")) {
          if (signal.aborted) return;
          yield { type: "message.part.delta", properties: { field: "text", delta: piece } };
          await sleep(tokenIntervalMs, signal);
        }
        yield { type: "session.idle" };
        return;
      }

      if (signal.aborted) return;

      // 3) 检索工具完成（completed，output=JSON 字符串）
      yield {
        type: "message.part.updated",
        properties: { part: { type: "tool", tool: LIGHTRAG_TOOL_NAME, state: { status: "completed", output: outputJson } } },
      };

      // 4) 流式答复 token
      for (const piece of chunkText(answer)) {
        if (signal.aborted) return;
        yield { type: "message.part.delta", properties: { field: "text", delta: piece } };
        await sleep(tokenIntervalMs, signal);
      }

      // 5) 会话空闲（完成信号）
      if (signal.aborted) return;
      yield { type: "session.idle" };
    },
  };
}
