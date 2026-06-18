/**
 * agent.ts
 * 用 Mastra Agent + createGraphRAGTool 封装查询层
 * Agent 自动决定何时走图谱、如何组织答案
 */

import { Mastra } from '@mastra/core'
import { Agent } from '@mastra/core/agent'
import { createGraphRAGTool } from '@mastra/rag'
import { llm, embeddingModel, config } from './config.js'
import type { FlameGraphRAG } from './indexer.js'

// ─── 创建带 GraphRAG 能力的 Mastra Agent ─────────────────────────

export function createFGAgent(fgRag: FlameGraphRAG) {
  // 把 FlameGraphRAG 实例包装成 Mastra 工具
  const graphRagTool = createGraphRAGTool({
    vectorStoreName: 'flamegraphVectorStore',
    indexName: 'flamegraph',
    model: embeddingModel,
    description: [
      'Query the flame graph knowledge graph to analyze CPU performance.',
      'Use this tool to find hot functions, call chains, bottlenecks,',
      'module-level CPU usage, and relationships between functions.',
    ].join(' '),
    graphOptions: {
      dimension: 1536,
      threshold: 0.65,
      randomWalkSteps: 150,
      restartProb: 0.15,
    },
  })

  const agent = new Agent({
    name: 'FlameGraph Analyst',
    model: llm,
    instructions: `
You are an expert performance engineer analyzing CPU flame graphs.
You have access to a knowledge graph built from a flame graph profile.

When answering questions:
1. Use the graphRagTool to retrieve relevant context from the knowledge graph
2. Identify hot functions (high CPU %) and their call chains
3. Explain bottlenecks clearly with percentages and sample counts
4. Suggest concrete optimization strategies based on findings
5. Connect related functions through their call relationships

Always cite specific function names, sample counts, and percentages.
Format your analysis in clear sections: Findings → Root Cause → Recommendations.
    `.trim(),
    tools: { graphRagTool },
  })

  return agent
}

// ─── Mastra 实例 ──────────────────────────────────────────────────

export function createMastra(agent: Agent) {
  return new Mastra({ agents: { flamegraphAgent: agent } })
}
