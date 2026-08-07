import { createCaseSearchMcpConfig } from "./case-search-server/mcp-config"

/**
 * 内置 MCP server 装配。
 *
 * 当前只有一个：`case_search`（神农知识库检索）。它是 opt-in 的——
 * 未配置 `CASE_KB_ID` 时 createCaseSearchMcpConfig 返回 undefined，
 * 此处便不注册，OpenCode 也就不会去拉起那个子进程。
 *
 * 注意：本函数只写自己的 key，绝不读改其他来源注册的 MCP。
 */
export type LocalMcpConfig = {
  type: "local"
  command: string[]
  environment?: Record<string, string>
  enabled: boolean
}

/** 本插件拥有的 MCP key，供 applyMcpsToConfig 做归属判断。 */
export const WITTY_MCP_NAMES = ["case_search"] as const

export function createBuiltinMcps(
  disabledMcps: readonly string[] = [],
): Record<string, LocalMcpConfig> {
  const mcps: Record<string, LocalMcpConfig> = {}
  const disabled = new Set(disabledMcps.map((m) => m.toLowerCase()))

  if (!disabled.has("case_search")) {
    const caseSearch = createCaseSearchMcpConfig()
    if (caseSearch) mcps.case_search = caseSearch
  }

  return mcps
}

/** 神农是否可用：知识库已配置（CASE_KB_ID）且 case_search 未被禁用。 */
export function isCaseSearchEnabled(
  disabledMcps: readonly string[] = [],
  env: Record<string, string | undefined> = process.env,
): boolean {
  const disabled = new Set(disabledMcps.map((m) => m.toLowerCase()))
  if (disabled.has("case_search")) return false
  return Boolean((env.CASE_KB_ID ?? "").trim())
}

export { createCaseSearchMcpConfig }
