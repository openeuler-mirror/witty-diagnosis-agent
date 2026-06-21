/**
 * 已知问题问答（QA / taiyi）模块 · 对外入口（web/server 端消费）。
 *
 * 这里只导出 **零外部依赖** 的「驱动 + LightRAG 客户端 + 规范化 schema」，供 web/server 直接 import。
 * 真实 opencode 路径的产物（QA agent 定义）放在 ./qa-agent.ts，**不在此 re-export**，以免把
 * @opencode-ai/sdk 带进 web 编译路径；知识检索的原生工具见 src/opencode/tools/lightrag/。
 *
 * 详见 ./README.md。
 */

export { createQaDriver, type QaDriverConfig } from "./driver/index.js";
export { LIGHTRAG_TOOL_NAME, type QaDriver, type QaDriverInput, type OpencodeEventPayload } from "./driver/types.js";
export {
  createLightragClient,
  LightragUnavailableError,
  type LightragClient,
  type LightragClientConfig,
  type LightragQueryInput,
  type LightragQueryMode,
} from "./lightrag/client.js";
export {
  parseLightragOutput,
  normalizeLightragResult,
  type LightragResult,
  type RetrievalLevels,
  type Citation,
  type CitationType,
  type GraphSubview,
  type GraphNode,
  type GraphEdge,
} from "./lightrag/schema.js";
