/**
 * 已知问题问答（QA）模块 · 驱动层契约。
 *
 * 「驱动」负责产出一条 **与 opencode 事件流同构** 的异步事件序列，供 web/server 的
 * qaEventSynthesizer 消费、合成 SSE。两种实现：
 *  - mock-driver：本期默认，直接调 LightRAG（mock）客户端合成事件，无需起 opencode/LLM。
 *  - opencode-driver（脚手架，real 路径）：createOpencode + session.promptAsync + event.subscribe，
 *    见 ../README.md；不被 web/server 编译路径 import（避免引入 @opencode-ai/sdk 依赖）。
 *
 * 事件形状严格对齐 opencode SDK `client.event.subscribe()`（确权：cli/run/types.ts:53-109、
 * event-handlers.ts:158-231）：顶层 `{ type, properties }`；文本增量在 message.part.delta
 * 的 properties.{field:"text", delta}；工具部件在 message.part.updated 的
 * properties.part.{type:"tool", tool, state:{status, output(string), error}}。
 *
 * 本文件零外部依赖，供 web/server 直接 import。
 */

/** opencode 事件流的最小载荷形状（仅取本模块所需字段）。 */
export interface OpencodeEventPayload {
  type: string;
  properties?: {
    field?: string;
    delta?: string;
    part?: {
      type?: string;
      tool?: string;
      name?: string;
      state?: {
        status?: string;
        output?: string;
        error?: string;
      };
    };
    [k: string]: unknown;
  };
}

export interface QaDriverInput {
  question: string;
  /** 续跑用的 opencode sessionId；首轮为空。 */
  sessionId?: string;
  /** 停止生成 / 超时中止。 */
  signal: AbortSignal;
}

export interface QaDriver {
  /** 解析/新建会话，返回 opencode sessionId（mock 下为生成的占位 id）。 */
  ensureSession(sessionId?: string): Promise<{ sessionId: string; contextReset: boolean }>;
  /** 发起一次问答，产出 opencode 同构事件流。 */
  run(input: QaDriverInput): AsyncGenerator<OpencodeEventPayload, void, unknown>;
}

/** QA agent 的工具名（LightRAG MCP），synthesizer 以此前缀识别检索工具部件。 */
export const LIGHTRAG_TOOL_NAME = "lightrag_query";
