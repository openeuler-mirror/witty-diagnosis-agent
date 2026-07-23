import type { Hooks } from "@opencode-ai/plugin"

import type { AgentDefinition } from "../agents/types"

/**
 * md-only 守护：mdOnly=true 的 agent（fuxi/dayu）只允许 edit/write .md 文件。
 *
 * 实现为 tool.execute.before 钩子：拦截文件写类工具，路径非 .md 时抛错，
 * 错误信息指导 agent 改为输出到计划/澄清文档。
 */

const FILE_WRITE_TOOLS = new Set(["edit", "write", "patch"])

export function createMdOnlyGuard(args: {
  definitions: readonly AgentDefinition[]
  /** 由调用方提供：sessionID → 当前 agent 名（插件在 chat.message 里维护映射） */
  resolveAgent: (sessionID: string) => string | undefined
}): NonNullable<Hooks["tool.execute.before"]> {
  const mdOnlyAgents = new Set(
    args.definitions.filter((d) => d.mdOnly).map((d) => d.name as string),
  )

  return async (input, output) => {
    if (!FILE_WRITE_TOOLS.has(input.tool)) return
    const agent = args.resolveAgent(input.sessionID)
    if (!agent || !mdOnlyAgents.has(agent)) return

    const filePath = extractFilePath(output.args)
    if (filePath === undefined || filePath.endsWith(".md")) return

    throw new Error(
      `${agent} 是规划/澄清类 agent，只允许写 .md 文档（拦截: ${filePath}）。` +
        `请把内容写入诊断计划或澄清文档。`,
    )
  }
}

function extractFilePath(toolArgs: unknown): string | undefined {
  if (typeof toolArgs !== "object" || toolArgs === null) return undefined
  const value = (toolArgs as Record<string, unknown>)["filePath"] ??
    (toolArgs as Record<string, unknown>)["file_path"] ??
    (toolArgs as Record<string, unknown>)["path"]
  return typeof value === "string" ? value : undefined
}
