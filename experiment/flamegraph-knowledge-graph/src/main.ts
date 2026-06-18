/**
 * main.ts
 * CLI 入口：读取火焰图文件 → 构建知识图谱 → 交互式查询
 *
 * 用法：
 *   npx tsx src/main.ts ./stacks.txt
 *   npx tsx src/main.ts ./flamegraph.svg
 *   npx tsx src/main.ts ./stacks.txt --query "哪个函数是最大的性能瓶颈？"
 */

import fs from 'fs'
import path from 'path'
import readline from 'readline'
import { parseFlameGraph } from './parser.js'
import { buildChunks } from './chunker.js'
import { FlameGraphRAG } from './indexer.js'
import { generateText } from 'ai'
import { llm } from './config.js'

// ─── 预设查询示例 ─────────────────────────────────────────────────

const EXAMPLE_QUERIES = [
  '哪个函数消耗了最多 CPU 时间？详细说明调用链。',
  '列出 CPU 占用超过 5% 的所有函数。',
  '找出最深的调用链路径，分析是否存在不必要的嵌套。',
  'Which module consumes the most CPU overall?',
  'Are there any recursive or circular call patterns?',
  'What are the top 3 bottlenecks and how to optimize them?',
]

// ─── 主流程 ───────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2)
  const filePath = args.find(a => !a.startsWith('--'))
  const queryFlag = args.indexOf('--query')
  const singleQuery = queryFlag !== -1 ? args[queryFlag + 1] : null
  const nonInteractive = args.includes('--no-interactive')

  if (!filePath) {
    console.error('Usage: npx tsx src/main.ts <flamegraph.txt|flamegraph.svg> [--query "..."]')
    process.exit(1)
  }

  // ── 1. 读取并解析文件 ──────────────────────────────────────────
  console.log(`\n🔥 FlameGraph GraphRAG Analyzer`)
  console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`)
  console.log(`📄 Reading: ${path.resolve(filePath)}`)

  const content = fs.readFileSync(filePath, 'utf-8')
  const ext = path.extname(filePath).toLowerCase()
  const hint = ext === '.svg' ? 'svg' : 'txt'

  console.log(`🔍 Parsing ${hint.toUpperCase()} format...`)
  const fg = parseFlameGraph(content, hint)

  console.log(`\n📊 Parse results:`)
  console.log(`   Unique functions : ${fg.frames.size}`)
  console.log(`   Call edges       : ${fg.edges.size}`)
  console.log(`   Total samples    : ${fg.totalSamples}`)
  console.log(`   Raw stacks       : ${fg.rawStacks.length}`)

  // ── 2. 构建 chunks ────────────────────────────────────────────
  console.log(`\n🧩 Building semantic chunks...`)
  const chunks = buildChunks(fg)
  console.log(`   Total chunks: ${chunks.length}`)
  const byType = chunks.reduce((a, c) => {
    a[c.metadata.type] = (a[c.metadata.type] ?? 0) + 1; return a
  }, {} as Record<string, number>)
  for (const [type, count] of Object.entries(byType)) {
    console.log(`   ${type.padEnd(12)}: ${count}`)
  }

  // ── 3. 构建 GraphRAG 知识图谱 ─────────────────────────────────
  const fgRag = new FlameGraphRAG({
    threshold: 0.65,
    randomWalkSteps: 150,
    topK: 12,
  })

  await fgRag.build(chunks)

  // ── 4. 查询模式 ───────────────────────────────────────────────

  if (singleQuery) {
    // 单次查询模式
    await runQuery(fgRag, singleQuery, fg.totalSamples)
    return
  }

  if (nonInteractive) {
    // 批量示例查询模式
    console.log('\n🤖 Running example queries...\n')
    for (const q of EXAMPLE_QUERIES.slice(0, 3)) {
      await runQuery(fgRag, q, fg.totalSamples)
      console.log()
    }
    return
  }

  // 交互式模式
  await interactiveMode(fgRag, fg.totalSamples)
}

// ─── 执行单次查询 ─────────────────────────────────────────────────

async function runQuery(fgRag: FlameGraphRAG, question: string, totalSamples: number) {
  console.log(`\n❓ Query: ${question}`)
  console.log('─'.repeat(60))

  const result = await fgRag.query(question)

  // 把检索到的上下文送给 LLM 生成最终回答
  const { text } = await generateText({
    model: llm,
    system: `You are an expert performance engineer analyzing CPU flame graphs.
Answer the user's question based ONLY on the provided flame graph context.
Always include: function names, sample counts, CPU percentages, and call relationships.
Format: clear bullet points or numbered list. Be concise and actionable.`,
    messages: [
      {
        role: 'user',
        content: `Flame graph context:\n\n${result.context}\n\n---\nQuestion: ${question}`,
      },
    ],
  })

  console.log(`\n💡 Answer:\n${text}`)

  // 展示原始检索节点（可选）
  if (process.env.DEBUG) {
    console.log(`\n📎 Retrieved nodes (${result.nodes.length}):`)
    for (const node of result.nodes.slice(0, 5)) {
      console.log(`  [${node.score.toFixed(3)}] ${node.id} (${node.metadata.type})`)
    }
  }
}

// ─── 交互式 REPL ──────────────────────────────────────────────────

async function interactiveMode(fgRag: FlameGraphRAG, totalSamples: number) {
  console.log('\n🎯 Interactive mode (type "exit" to quit, "examples" to see sample queries)')
  console.log('─'.repeat(60))

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  })

  const ask = () => {
    rl.question('\n🔍 Query> ', async (input) => {
      const q = input.trim()

      if (!q || q === 'exit' || q === 'quit') {
        console.log('Bye!')
        rl.close()
        return
      }

      if (q === 'examples') {
        console.log('\nExample queries:')
        EXAMPLE_QUERIES.forEach((eq, i) => console.log(`  ${i + 1}. ${eq}`))
        ask()
        return
      }

      try {
        await runQuery(fgRag, q, totalSamples)
      } catch (e: any) {
        console.error('Error:', e.message)
      }

      ask()
    })
  }

  ask()
}

main().catch(e => {
  console.error('Fatal:', e)
  process.exit(1)
})
