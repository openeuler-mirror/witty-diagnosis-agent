/**
 * LightRAG 知识检索 · opencode 原生工具（替代原 stdio MCP server）。
 *
 * 直接对接 LightRAG REST `/query`（见 http://localhost:9621/redoc#tag/query），
 * 把规范化后的 LightragResult 以 **JSON 字符串** 作为工具输出返回（对齐 02 §2.2.2 / DQ-002：
 * opencode tool 的 output 为 string，结构化检索数据经 JSON 字符串承载、后端再解析）。
 *
 * 设计要点：
 *  - **零 MCP 依赖**：不再起 stdio JSON-RPC 子进程，agent 直接调用本工具 → 复用零依赖的
 *    `RestLightragClient`（agents/taiyi/lightrag/client.ts）。
 *  - **lazy 连接**：仅在被调用时才发起网络请求；端点不可达/超时只返回结构化 error，不抛、不崩，
 *    上游优雅降级（BC-006/NFR-001/S-007）。
 *  - **配置全部经环境变量注入**（不入库、不打印，NFR-004）：
 *      LIGHTRAG_ENDPOINT（默认 http://localhost:9621）
 *      LIGHTRAG_API_KEY（默认 lightrag1234）
 *      LIGHTRAG_API_KEY_HEADER（默认 X-API-Key）
 *      LIGHTRAG_QUERY_MODE（默认 mix）
 *      LIGHTRAG_TIMEOUT_MS（默认 30000）
 *      LIGHTRAG_RESPONSE_TYPE（默认 "Multiple Paragraphs"）
 *      LIGHTRAG_INCLUDE_CHUNK_CONTENT（默认 true；设 "false" 关闭）
 *      LIGHTRAG_MOCK（设 "true" 走内置 mock 知识，便于未灌库联调）
 */

import type { ToolDefinition } from "@opencode-ai/plugin"
import { tool } from "@opencode-ai/plugin/tool"
import {
  createLightragClient,
  LightragUnavailableError,
  type LightragClientConfig,
  type LightragQueryMode,
} from "./client"

export const LIGHTRAG_QUERY_TOOL_NAME = "lightrag_query"

const QUERY_MODES = ["local", "global", "hybrid", "naive", "mix", "bypass"] as const

function readQueryMode(): LightragQueryMode {
  const mode = process.env.LIGHTRAG_QUERY_MODE
  return (QUERY_MODES as readonly string[]).includes(mode ?? "")
    ? (mode as LightragQueryMode)
    : "mix"
}

/** 从环境变量读取 LightRAG 接入配置（默认对接本地 9621 真实服务）。 */
export function readLightragConfig(): LightragClientConfig {
  return {
    mock: process.env.LIGHTRAG_MOCK === "true",
    endpoint: process.env.LIGHTRAG_ENDPOINT || "http://localhost:9621",
    apiKey: process.env.LIGHTRAG_API_KEY || "lightrag1234",
    apiKeyHeader: process.env.LIGHTRAG_API_KEY_HEADER || "X-API-Key",
    timeoutMs: Number(process.env.LIGHTRAG_TIMEOUT_MS) || 30000,
    defaultMode: readQueryMode(),
    responseType: process.env.LIGHTRAG_RESPONSE_TYPE || "Multiple Paragraphs",
    includeChunkContent: process.env.LIGHTRAG_INCLUDE_CHUNK_CONTENT !== "false",
  }
}

export function createLightragTool(): Record<string, ToolDefinition> {
  const lightrag_query: ToolDefinition = tool({
    description:
      "检索运维知识库（LightRAG /query 双层检索：low 精确实体/关系 + high 主题/概念）。返回 JSON 字符串：{answer_context, retrieval, sources[], graph, followups}。只读，不执行任何主机操作。",
    args: {
      question: tool.schema.string().describe("运维问题（自然语言）。"),
      mode: tool.schema
        .enum(["hybrid", "local", "global", "naive", "mix", "bypass"])
        .optional()
        .describe("检索模式，默认 hybrid。"),
    },
    execute: async (args) => {
      const question = (args.question ?? "").trim()
      if (!question) {
        return JSON.stringify({ error: "question is required" })
      }
      const client = createLightragClient(readLightragConfig()) // lazy：此处不触发网络
      try {
        const res = await client.query({
          question,
          mode: (args.mode as LightragQueryMode) ?? "hybrid",
        })
        // 结构化结果以 JSON 字符串承载（后端 JSON.parse + 校验 + 降级）
        return JSON.stringify(res)
      } catch (err) {
        const message =
          err instanceof LightragUnavailableError ? err.message : "知识检索服务暂不可用"
        // 工具级错误：返回结构化 error，让上游优雅降级（S-007），不抛出
        return JSON.stringify({ error: message })
      }
    },
  })

  return { lightrag_query }
}
