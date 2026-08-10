import { mkdirSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import type { CaseHit } from "./types"

/**
 * Writes the hit cases (name / content / content_after_preprocess only) to a
 * single markdown file and returns its absolute path.
 *
 * The full case bodies are kept OUT of the model context: the search tool only
 * returns this file path (+ the list of case names), and the downstream Kuafu
 * agent reads the file directly. This avoids inlining large JSON into the plan.
 *
 * Returns null on any failure (graceful degradation — the caller treats it as
 * "no cases file available").
 */
export function writeCasesFile(
  casesDir: string,
  query: string,
  kbId: string,
  hits: CaseHit[],
): string | null {
  if (hits.length === 0) return null

  try {
    mkdirSync(casesDir, { recursive: true })

    const ts = new Date().toISOString().replace(/[:.]/g, "-")
    const kbTag = (kbId || "kb").slice(0, 8)
    const fileName = `${ts}_${kbTag}.md`
    const filePath = join(casesDir, fileName)

    const body = renderCasesMarkdown(query, hits)
    writeFileSync(filePath, body, "utf-8")
    return filePath
  } catch {
    return null
  }
}

/** Render hit cases as markdown — only name / content / content_after_preprocess. */
function renderCasesMarkdown(query: string, hits: CaseHit[]): string {
  const lines: string[] = []
  lines.push(`# 已知问题案例 (Known-Issue Cases)`)
  lines.push("")
  lines.push(`> 检索查询: ${query}`)
  lines.push(`> 命中数量: ${hits.length}`)
  lines.push(
    `> 说明: 以下为知识库历史案例原文，仅供诊断排查方向参考，最终根因须以本次实际取证为准。`,
  )
  lines.push("")

  hits.forEach((hit, i) => {
    lines.push(`## ${i + 1}. ${hit.name || "(无标题)"}`)
    lines.push("")
    lines.push(`### content`)
    lines.push("")
    lines.push("```json")
    lines.push(JSON.stringify(hit.content, null, 2))
    lines.push("```")
    lines.push("")
    lines.push(`### content_after_preprocess`)
    lines.push("")
    lines.push("```json")
    lines.push(JSON.stringify(hit.content_after_preprocess, null, 2))
    lines.push("```")
    lines.push("")
  })

  return lines.join("\n")
}
