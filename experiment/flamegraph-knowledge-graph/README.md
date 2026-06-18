# FlameGraph GraphRAG

基于 **Mastra GraphRAG** 的火焰图智能分析工具。
把 CPU 火焰图（折叠栈 `.txt` 或 FlameGraph `.svg`）转化为知识图谱，
用自然语言查询性能瓶颈、调用链关系和优化建议。

---

## 整体架构

```
火焰图文件 (txt/svg)
        │
        ▼
  ┌─────────────┐
  │   parser.ts  │  解析折叠栈/SVG → 函数节点 + 调用边
  └──────┬──────┘
         │
         ▼
  ┌─────────────┐
  │  chunker.ts  │  构建语义 chunk（4 种类型）
  └──────┬──────┘
         │  Function chunk
         │  CallEdge chunk
         │  Module chunk
         │  CallPath chunk
         ▼
  ┌────────────────────┐
  │    indexer.ts       │  embedMany → GraphRAG.createGraph()
  │  (FlameGraphRAG)    │  建立知识图谱（节点=chunk，边=语义相似）
  └──────┬─────────────┘
         │
         ▼
  ┌──────────────────────────────┐
  │  自然语言查询                  │
  │  embed(question)             │
  │  → graphRag.query()          │  随机游走图遍历
  │  → context chunks            │
  │  → LLM generateText()        │  GPT-4o-mini 生成分析
  └──────────────────────────────┘
```

---

## 安装

```bash
git clone <this-repo>
cd flamegraph-graphrag
npm install

# 配置 OpenAI API Key
export OPENAI_API_KEY=sk-...
```

---

## 使用

### 命令行分析

```bash
# 分析 txt 格式（折叠栈）
npx tsx src/main.ts ./sample.txt

# 分析 svg 格式
npx tsx src/main.ts ./flamegraph.svg

# 单次查询（非交互）
npx tsx src/main.ts ./sample.txt --query "哪个函数是最大的性能瓶颈？"

# 批量示例查询
npx tsx src/main.ts ./sample.txt --no-interactive

# 调试模式（显示检索节点）
DEBUG=1 npx tsx src/main.ts ./sample.txt
```

### 编程接口

```typescript
import { parseFlameGraph } from './src/parser.js'
import { buildChunks } from './src/chunker.js'
import { FlameGraphRAG } from './src/indexer.js'
import { generateText } from 'ai'
import { openai } from '@ai-sdk/openai'
import fs from 'fs'

async function analyzeFG(filePath: string, question: string) {
  // 1. 解析
  const content = fs.readFileSync(filePath, 'utf-8')
  const fg = parseFlameGraph(content)          // 自动检测 txt/svg

  // 2. 构建 chunks
  const chunks = buildChunks(fg)

  // 3. 构建知识图谱
  const fgRag = new FlameGraphRAG({
    threshold: 0.65,       // 建边相似度阈值
    randomWalkSteps: 150,  // 图遍历步数
    topK: 12,              // 返回节点数
  })
  await fgRag.build(chunks)

  // 4. 查询
  const { context, nodes } = await fgRag.query(question)

  // 5. LLM 生成分析
  const { text } = await generateText({
    model: openai('gpt-4o-mini'),
    system: 'You are a performance engineer. Analyze the flame graph context.',
    messages: [{ role: 'user', content: `Context:\n${context}\n\nQuestion: ${question}` }],
  })

  return { answer: text, nodes }
}
```

---

## Chunk 类型说明

| 类型 | 内容 | 用途 |
|------|------|------|
| `function` | 单个函数的 samples/pct/depth | 查询特定函数 CPU 占用 |
| `call_path` | 调用边 caller→callee 及权重 | 查询函数间调用关系 |
| `hot_module` | 模块级聚合统计 | 查询哪个模块整体消耗大 |
| `call_chain` | 完整调用链（top 50） | 查询端到端热路径 |

---

## GraphRAG 参数调优

```typescript
new FlameGraphRAG({
  threshold: 0.65,      // 越低图越密，连通性越强，但噪音增加
                        // 越高图越稀疏，结果更精确但可能漏掉关联
  randomWalkSteps: 150, // 步数越多，探索范围越广，适合"分析全局"
                        // 步数少，结果更聚焦，适合"找某个函数"
  restartProb: 0.15,    // 0.15 = 每步 15% 概率重置到 query 节点
                        // 高 restartProb → 更倾向 query 直接相似的节点
  topK: 12,             // 返回最相关的 12 个节点送给 LLM
})
```

---

## 支持的查询示例

```
哪个函数消耗了最多 CPU 时间？
列出所有 CPU 占用超过 5% 的函数
pg_exec 是被哪些函数调用的？
compress_data 的完整调用链是什么？
哪个模块整体 CPU 开销最大？
是否存在递归调用？
给出 top 3 性能优化建议
Which functions call into the database layer?
What is the critical path from main to the hottest leaf?
```

---

## 文件结构

```
src/
├── parser.ts    # 解析 txt/svg → ParsedFlameGraph
├── chunker.ts   # ParsedFlameGraph → FGChunk[]
├── indexer.ts   # FGChunk[] → GraphRAG 知识图谱 + query()
├── agent.ts     # Mastra Agent（完整 agent 模式，可选）
└── main.ts      # CLI 入口
sample.txt       # 示例火焰图
```
