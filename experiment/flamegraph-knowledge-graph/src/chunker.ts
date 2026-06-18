/**
 * chunker.ts
 * 把解析后的火焰图转化为适合 GraphRAG 的文档 chunk
 * 每个 chunk 代表一个有意义的语义单元（函数、调用路径、热点模块）
 */

import type { ParsedFlameGraph, StackFrame, CallEdge } from './parser.js'

export interface FGChunk {
  id: string
  text: string                    // 送入 embedding 的文本
  metadata: {
    type: 'function' | 'call_path' | 'hot_module' | 'call_chain'
    name?: string
    module?: string
    samples?: number
    pct?: number
    depth?: number
    caller?: string
    callee?: string
    path?: string[]
    rank?: number
  }
}

// ─── 主入口 ───────────────────────────────────────────────────────

export function buildChunks(fg: ParsedFlameGraph): FGChunk[] {
  const chunks: FGChunk[] = []
  const total = fg.totalSamples || 1

  // 1. 每个函数节点 → 一个 chunk
  chunks.push(...buildFunctionChunks(fg.frames, total))

  // 2. 每条调用边 → 一个 chunk
  chunks.push(...buildCallEdgeChunks(fg.edges, total))

  // 3. 按模块聚合 → 热点模块 chunk
  chunks.push(...buildModuleChunks(fg.frames, total))

  // 4. 完整调用链（从 rawStacks 重建，取 top 50）
  if (fg.rawStacks.length > 0) {
    chunks.push(...buildCallPathChunks(fg.rawStacks, total))
  }

  return chunks
}

// ─── 函数节点 chunks ──────────────────────────────────────────────

function buildFunctionChunks(
  frames: Map<string, StackFrame>,
  total: number
): FGChunk[] {
  return Array.from(frames.values())
    .sort((a, b) => b.samples - a.samples)
    .map((frame, idx) => {
      const pct = ((frame.samples / total) * 100).toFixed(2)
      return {
        id: `func:${frame.name}`,
        text: [
          `Function: ${frame.name}`,
          `Module: ${frame.module}`,
          `CPU samples: ${frame.samples} (${pct}% of total)`,
          `Call depth: ${frame.depth}`,
          `This function "${frame.name}" belongs to module "${frame.module}".`,
          `It consumed ${pct}% of CPU time with ${frame.samples} samples.`,
          idx < 10
            ? `This is a hot function ranked #${idx + 1} by CPU usage.`
            : '',
        ].filter(Boolean).join('\n'),
        metadata: {
          type: 'function' as const,
          name: frame.name,
          module: frame.module,
          samples: frame.samples,
          pct: parseFloat(pct),
          depth: frame.depth,
          rank: idx + 1,
        },
      }
    })
}

// ─── 调用边 chunks ────────────────────────────────────────────────

function buildCallEdgeChunks(
  edges: Map<string, CallEdge>,
  total: number
): FGChunk[] {
  return Array.from(edges.values())
    .sort((a, b) => b.samples - a.samples)
    .slice(0, 200) // 限制边数量，避免 chunk 过多
    .map(edge => {
      const pct = ((edge.samples / total) * 100).toFixed(2)
      return {
        id: `edge:${edge.caller}→${edge.callee}`,
        text: [
          `Call relationship: ${edge.caller} calls ${edge.callee}`,
          `Samples on this path: ${edge.samples} (${pct}%)`,
          `"${edge.caller}" directly calls "${edge.callee}".`,
          `This call path accounts for ${pct}% of CPU usage.`,
        ].join('\n'),
        metadata: {
          type: 'call_path' as const,
          caller: edge.caller,
          callee: edge.callee,
          samples: edge.samples,
          pct: parseFloat(pct),
        },
      }
    })
}

// ─── 模块聚合 chunks ──────────────────────────────────────────────

function buildModuleChunks(
  frames: Map<string, StackFrame>,
  total: number
): FGChunk[] {
  const moduleMap = new Map<string, { samples: number; fns: string[] }>()

  for (const frame of frames.values()) {
    const mod = moduleMap.get(frame.module)
    if (mod) {
      mod.samples += frame.samples
      mod.fns.push(frame.name)
    } else {
      moduleMap.set(frame.module, { samples: frame.samples, fns: [frame.name] })
    }
  }

  return Array.from(moduleMap.entries())
    .sort((a, b) => b[1].samples - a[1].samples)
    .map(([modName, data]) => {
      const pct = ((data.samples / total) * 100).toFixed(2)
      const topFns = data.fns
        .slice(0, 5)
        .map(f => `  - ${f}`)
        .join('\n')
      return {
        id: `module:${modName}`,
        text: [
          `Module: ${modName}`,
          `Total CPU samples: ${data.samples} (${pct}%)`,
          `Function count: ${data.fns.length}`,
          `Top functions in this module:\n${topFns}`,
          `The module "${modName}" consumed ${pct}% of CPU time total.`,
        ].join('\n'),
        metadata: {
          type: 'hot_module' as const,
          module: modName,
          samples: data.samples,
          pct: parseFloat(pct),
        },
      }
    })
}

// ─── 完整调用链 chunks ────────────────────────────────────────────

function buildCallPathChunks(
  rawStacks: Array<{ stack: string[]; samples: number }>,
  total: number
): FGChunk[] {
  return rawStacks
    .sort((a, b) => b.samples - a.samples)
    .slice(0, 50) // 只取最热的 50 条完整路径
    .map((raw, idx) => {
      const pct = ((raw.samples / total) * 100).toFixed(2)
      const pathStr = raw.stack.join(' → ')
      return {
        id: `path:${idx}`,
        text: [
          `Hot call path #${idx + 1}: ${pathStr}`,
          `Samples: ${raw.samples} (${pct}%)`,
          `Call depth: ${raw.stack.length}`,
          `Entry point: ${raw.stack[0]}`,
          `Leaf function: ${raw.stack[raw.stack.length - 1]}`,
          `This execution path starts from "${raw.stack[0]}" `,
          `and ends at "${raw.stack[raw.stack.length - 1]}", `,
          `consuming ${pct}% of total CPU time.`,
        ].join('\n'),
        metadata: {
          type: 'call_chain' as const,
          path: raw.stack,
          samples: raw.samples,
          pct: parseFloat(pct),
          depth: raw.stack.length,
        },
      }
    })
}
