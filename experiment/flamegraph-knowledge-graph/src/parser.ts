/**
 * parser.ts
 * 解析火焰图的两种格式：折叠栈 txt 和 SVG
 */

export interface StackFrame {
  name: string        // 函数名
  module: string      // 所属模块（从命名空间推断）
  depth: number       // 栈深度
  samples: number     // 采样次数
}

export interface CallEdge {
  caller: string
  callee: string
  samples: number
}

export interface ParsedFlameGraph {
  frames: Map<string, StackFrame>   // 所有唯一函数节点
  edges: Map<string, CallEdge>      // 调用关系边
  totalSamples: number
  rawStacks: Array<{ stack: string[]; samples: number }>
}

// ─── 解析折叠栈格式 txt ───────────────────────────────────────────
// 每行格式：func_a;func_b;func_c 42

export function parseCollapsedTxt(content: string): ParsedFlameGraph {
  const frames = new Map<string, StackFrame>()
  const edges = new Map<string, CallEdge>()
  const rawStacks: Array<{ stack: string[]; samples: number }> = []
  let totalSamples = 0

  for (const line of content.trim().split('\n')) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue

    const lastSpace = trimmed.lastIndexOf(' ')
    if (lastSpace === -1) continue

    const stackStr = trimmed.slice(0, lastSpace)
    const samples = parseInt(trimmed.slice(lastSpace + 1), 10)
    if (isNaN(samples)) continue

    const stack = stackStr.split(';').map(s => s.trim()).filter(Boolean)
    if (stack.length === 0) continue

    totalSamples += samples
    rawStacks.push({ stack, samples })

    // 叶子节点：self samples；所有节点：total samples
    for (let i = 0; i < stack.length; i++) {
      const fnName = stack[i]
      const existing = frames.get(fnName)
      if (existing) {
        existing.samples += samples
        existing.depth = Math.min(existing.depth, i)
      } else {
        frames.set(fnName, {
          name: fnName,
          module: inferModule(fnName),
          depth: i,
          samples,
        })
      }

      // 建立调用边（相邻帧）
      if (i < stack.length - 1) {
        const callee = stack[i + 1]
        const edgeKey = `${fnName}→${callee}`
        const edge = edges.get(edgeKey)
        if (edge) {
          edge.samples += samples
        } else {
          edges.set(edgeKey, { caller: fnName, callee, samples })
        }
      }
    }
  }

  return { frames, edges, totalSamples, rawStacks }
}

// ─── 解析 SVG 格式 ───────────────────────────────────────────────
// FlameGraph SVG 中每个 <g> 包含 <title> 和 <rect>
// title 格式通常是 "func_name (N samples, X%)"

export function parseSvg(svgContent: string): ParsedFlameGraph {
  // 提取所有 <title> 标签内容
  const titlePattern = /<title>([^<]+)<\/title>/g
  const rectPattern = /<rect[^>]+x="([^"]+)"[^>]+y="([^"]+)"[^>]+width="([^"]+)"/g

  const titleMatches: string[] = []
  let m: RegExpExecArray | null

  while ((m = titlePattern.exec(svgContent)) !== null) {
    titleMatches.push(m[1])
  }

  const frames = new Map<string, StackFrame>()
  const edges = new Map<string, CallEdge>()

  // SVG 里无法直接还原完整调用链，但可以从 y 坐标推断深度
  // 同 x 区间内不同 y 的帧是调用关系
  const rects: Array<{ x: number; y: number; width: number; title: string }> = []

  // 重新匹配带 title 的 <g> 块
  const gPattern = /<g[^>]*>[\s\S]*?<title>([^<]+)<\/title>[\s\S]*?<rect[^>]+x="([\d.]+)"[^>]+y="([\d.]+)"[^>]+width="([\d.]+)"/g

  while ((m = gPattern.exec(svgContent)) !== null) {
    const title = m[1]
    const x = parseFloat(m[2])
    const y = parseFloat(m[3])
    const width = parseFloat(m[4])

    // 解析 title：格式如 "pg_exec (320 samples, 68.00%)"
    const sampleMatch = title.match(/^(.+?)\s*\((\d+)\s+samples?/)
    if (!sampleMatch) continue

    const fnName = sampleMatch[1].trim()
    const samples = parseInt(sampleMatch[2], 10)

    rects.push({ x, y, width, title: fnName })

    const existing = frames.get(fnName)
    if (existing) {
      existing.samples += samples
    } else {
      frames.set(fnName, {
        name: fnName,
        module: inferModule(fnName),
        depth: Math.round(y / 16), // 通常每帧高度 15-16px
        samples,
      })
    }
  }

  // 通过 x/y 坐标推断调用关系：
  // callee 的 x 区间包含在 caller 的 x 区间内，且 y 值更小（更深）
  rects.sort((a, b) => b.y - a.y) // y 大的在底部（调用者）

  for (let i = 0; i < rects.length; i++) {
    const caller = rects[i]
    for (let j = i + 1; j < rects.length; j++) {
      const callee = rects[j]
      if (
        callee.y < caller.y &&
        callee.x >= caller.x - 1 &&
        callee.x + callee.width <= caller.x + caller.width + 1
      ) {
        const edgeKey = `${caller.title}→${callee.title}`
        if (!edges.has(edgeKey)) {
          edges.set(edgeKey, {
            caller: caller.title,
            callee: callee.title,
            samples: frames.get(callee.title)?.samples ?? 0,
          })
        }
      }
    }
  }

  const totalSamples = Array.from(frames.values()).reduce(
    (sum, f) => (f.depth === 0 ? sum + f.samples : sum), 0
  )

  return { frames, edges, totalSamples, rawStacks: [] }
}

// ─── 工具函数 ─────────────────────────────────────────────────────

function inferModule(fnName: string): string {
  // Java/Kotlin: com.example.service.Foo.method → com.example.service
  if (fnName.includes('.') && /[a-z]/.test(fnName[0])) {
    const parts = fnName.split('.')
    return parts.slice(0, Math.min(3, parts.length - 1)).join('.')
  }
  // Rust/C++: module::submodule::fn → module::submodule
  if (fnName.includes('::')) {
    const parts = fnName.split('::')
    return parts.slice(0, Math.max(1, parts.length - 1)).join('::')
  }
  // Go: github.com/pkg/sub.Func → github.com/pkg/sub
  if (fnName.includes('/')) {
    const parts = fnName.split('/')
    const last = parts[parts.length - 1].split('.')
    return [...parts.slice(0, -1), last[0]].join('/')
  }
  // 下划线分隔：kernel_do_fork → kernel
  if (fnName.includes('_')) {
    return fnName.split('_')[0]
  }
  return 'unknown'
}

// ─── 自动检测格式并解析 ───────────────────────────────────────────

export function parseFlameGraph(content: string, hint?: 'txt' | 'svg'): ParsedFlameGraph {
  const isSvg = hint === 'svg' ||
    (!hint && (content.trimStart().startsWith('<svg') || content.includes('<svg')))

  return isSvg ? parseSvg(content) : parseCollapsedTxt(content)
}
