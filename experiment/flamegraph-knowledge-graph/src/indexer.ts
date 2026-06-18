/**
 * indexer.ts
 * 把 FGChunk[] 送入 Mastra GraphRAG，构建知识图谱并提供查询接口
 */

import { GraphRAG, MDocument } from '@mastra/rag'
import { embed, embedMany } from 'ai'
import { embeddingModel, config } from './config.js'
import type { FGChunk } from './chunker.js'

// ─── 配置 ─────────────────────────────────────────────────────────

const EMBEDDING_MODEL = embeddingModel
const EMBEDDING_DIM = config.embeddingDim

export interface FGGraphRAGOptions {
  /** 建边的余弦相似度阈值，越高图越稀疏 */
  threshold?: number
  /** 随机游走步数，越大探索越广 */
  randomWalkSteps?: number
  /** 每次游走重启概率 */
  restartProb?: number
  /** 返回的最大节点数 */
  topK?: number
}

// ─── 主类 ─────────────────────────────────────────────────────────

export class FlameGraphRAG {
  private graphRag: GraphRAG
  private chunks: FGChunk[] = []
  private options: Required<FGGraphRAGOptions>
  private built = false

  constructor(opts: FGGraphRAGOptions = {}) {
    this.options = {
      threshold: opts.threshold ?? 0.65,        // 火焰图语义较密集，阈值略低
      randomWalkSteps: opts.randomWalkSteps ?? 150,
      restartProb: opts.restartProb ?? 0.15,
      topK: opts.topK ?? 10,
    }
    this.graphRag = new GraphRAG(EMBEDDING_DIM)
  }

  // ─── 构建索引 ──────────────────────────────────────────────────

  async build(chunks: FGChunk[]): Promise<void> {
    if (chunks.length === 0) throw new Error('No chunks to index')
    this.chunks = chunks

    console.log(`\n[GraphRAG] Embedding ${chunks.length} chunks...`)

    // 批量 embedding（避免超 rate limit，每批 100 条）
    const texts = chunks.map(c => c.text)
    const allEmbeddings: number[][] = []

    for (let i = 0; i < texts.length; i += 100) {
      const batch = texts.slice(i, i + 100)
      const { embeddings } = await embedMany({
        model: EMBEDDING_MODEL,
        values: batch,
      })
      allEmbeddings.push(...embeddings)
      process.stdout.write(`  ${Math.min(i + 100, texts.length)}/${texts.length}\r`)
    }

    // 转成 Mastra GraphRAG 需要的格式
    const graphChunks = chunks.map((c, idx) => ({
      id: c.id,
      text: c.text,
      metadata: c.metadata,
      // MDocument 兼容格式
      pageContent: c.text,
    }))

    const graphEmbeddings = allEmbeddings.map((emb, idx) => ({
      vector: emb,
      id: chunks[idx].id,
    }))

    console.log('\n[GraphRAG] Building knowledge graph...')
    this.graphRag.createGraph(graphChunks, graphEmbeddings)
    this.built = true
    console.log('[GraphRAG] ✓ Knowledge graph ready\n')
  }

  // ─── 查询 ──────────────────────────────────────────────────────

  async query(question: string): Promise<QueryResult> {
    if (!this.built) throw new Error('Call build() first')

    // 把问题 embedding
    const { embedding: queryEmbedding } = await embed({
      model: EMBEDDING_MODEL,
      value: question,
    })

    // 图遍历检索
    const nodes = await this.graphRag.query({
      query: queryEmbedding,
      topK: this.options.topK,
      randomWalkSteps: this.options.randomWalkSteps,
      restartProb: this.options.restartProb,
    })

    // 组装上下文
    const context = nodes
      .map(n => `[score: ${n.score.toFixed(3)}]\n${n.content}`)
      .join('\n\n---\n\n')

    return {
      question,
      context,
      nodes: nodes.map(n => ({
        id: n.id,
        score: n.score,
        content: n.content,
        metadata: n.metadata || {},
      })),
    }
  }

  // ─── 统计信息 ──────────────────────────────────────────────────

  stats() {
    return {
      totalChunks: this.chunks.length,
      byType: this.chunks.reduce((acc, c) => {
        acc[c.metadata.type] = (acc[c.metadata.type] ?? 0) + 1
        return acc
      }, {} as Record<string, number>),
    }
  }
}

export interface QueryResult {
  question: string
  context: string
  nodes: Array<{
    id: string
    score: number
    content: string
    metadata: Record<string, any>
  }>
}
