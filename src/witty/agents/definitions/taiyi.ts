import type { AgentDefinition } from "../types"

/** 太乙：运维问答 agent。与旧版一致：primary 模式、temperature 0.1、只读检索。 */
export const taiyi: AgentDefinition = {
  name: "taiyi",
  displayName: "太乙",
  description:
    "IT 运维问答：检索运维知识库（LightRAG），并在配置联网检索时辅以网络搜索，带出处与引用作答；只读，不执行任何主机操作",
  descriptionEn:
    "IT-ops Q&A: retrieves the ops knowledge base (LightRAG), augments with web search when configured, and answers with explicit citations; read-only, no host actions",
  mode: "primary",
  promptFile: "taiyi.md",
  temperature: 0.1,
  permission: {
    edit: "deny",
    bash: "deny",
    task: "deny",
  },
  tools: { lightrag_query: true },
  color: "#7F8C8D",
}
