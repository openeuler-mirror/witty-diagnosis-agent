import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js"
import { z } from "zod"
import { CaseSearchClient } from "./client"
import type { LogicalExpression } from "./types"

/**
 * Case-search MCP server (stdio).
 *
 * Exposes a single tool `search_jsons` that the Shennong (神农) known-issue
 * analysis sub-agent uses to retrieve related known-issue cases from the
 * Knowledge-Base RAG service exposed at POST /json/search.
 *
 * Parameters exposed to the model are intentionally limited to `query` and the
 * optional `logical_expression`. `kb_id` is injected from the environment by the
 * client/config layer and is never decided by the model.
 *
 * Run as a stdio MCP via OpenCode's `type: "local"` config, e.g.:
 *   { "case_search": {
 *       "type": "local",
 *       "command": ["node", "dist/mcp/case-search-server/cli.js"],
 *       "environment": { "CASE_API_BASE_URL": "...", "CASE_KB_ID": "..." }
 *   } }
 */

// Recursive zod schema for the optional logical_expression filter. Leaf nodes
// are plain objects (Condition) so we keep the group schema permissive.
const logicalExpressionSchema: z.ZodType<LogicalExpression> = z.lazy(() =>
  z.object({
    operator: z.string().describe("逻辑运算符，如 and / or"),
    expressions: z
      .array(z.union([logicalExpressionSchema, z.record(z.string(), z.unknown())]))
      .describe("逻辑表达式列表：可嵌套子表达式，或为叶子条件 {field, operator, value}"),
  }),
)

export function createCaseSearchServer(client: CaseSearchClient): McpServer {
  const server = new McpServer({
    name: "case-search",
    version: "0.1.0",
  })

  server.registerTool(
    "search_jsons",
    {
      title: "Search known-issue cases",
      description:
        "检索与日志/异常特征相关的已知问题案例 (POST /json/search)。kb_id 由服务端环境变量注入，无需传入。" +
        "传入 query（由日志解析/异常检测得到的检索查询）以及可选的 logical_expression（由 euler-rag-json-search skill 生成的结构化过滤条件）。" +
        "命中案例的完整原文（name/content/content_after_preprocess）会被写入一个 markdown 文件，工具只返回 { cases_file: 文件绝对路径, cases: [{id, name}] }（无命中时 cases_file 为 null）。" +
        "后续由 Kuafu 直接读取该文件，避免把大 JSON 塞进上下文。供伏羲(Fuxi)做诊断规划参考，仅做案例关联，不下根因结论。",
      inputSchema: {
        query: z
          .string()
          .describe("由日志解析/异常检测得到的检索查询（错误码、组件名、堆栈关键词等）"),
        logical_expression: logicalExpressionSchema
          .optional()
          .describe(
            "可选的结构化过滤条件，符合 知识库 RAG 服务的 LogicalExpression 结构；通常由 euler-rag-json-search skill 产出",
          ),
      },
    },
    async ({ query, logical_expression }) => {
      const result = await client.searchJsons({
        query,
        logicalExpression: logical_expression,
      })
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      }
    },
  )

  return server
}
