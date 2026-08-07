# taiyi · IT 运维问答（QA 后端核心）

本目录是「IT 运维问答 Agent」的**后端核心**（设计见
`docs/design/known-fault-dialog-interaction/`）。该 agent 面向运维工程师 / SRE，回答**一切 IT 运维
相关问题**（系统/网络/存储/容器/数据库/中间件/监控/排障/最佳实践等），核心能力是**检索知识库
（LightRAG）+（若配置联网检索）网络搜索**，据证据组织带出处的回答；只读、不执行任何主机操作。
按约定，**前端**在 `src/witty/web/frontend`，**后端 HTTP/持久化层**在 `src/witty/web/server`，
而**问答“大脑”（驱动 + LightRAG 接入 + agent 定义）在本目录**。

## 模块边界（重要）

为保证 `web/server` 编译路径（`tsc --noEmit`，仅 node 依赖）干净，本目录分两类文件：

| 类别 | 文件 | 依赖 | 是否被 web/server import |
|---|---|---|---|
| **Web 可导入核心**（零外部依赖） | `index.ts`、`driver/*`、`lightrag/client.ts`、`lightrag/schema.ts` | 仅 node 内置（fetch/crypto） | ✅ 是 |
| **真实 opencode 路径**（脚手架） | `qa-agent.ts` | `@opencode-ai/sdk` | ❌ 否 |

`web/server` 只 `import` 第一类（经本目录 `index.ts`）。第二类是把 mock 驱动换成真实
opencode 常驻 server 时才接入的产物，单独存在、互不牵连。

> 知识检索不再走 stdio MCP 子进程：opencode 真实路径下由**原生工具** `lightrag_query`
> （`src/witty/tools/lightrag/`，全局注册）直接对接 LightRAG REST `/query`，复用本目录零依赖的
> `lightrag/client.ts`。

## 数据流（本期 = mock 优先）

```
qaRunner(web/server)
  └─ createQaDriver()  ── driver/mock-driver.ts
       ├─ lightrag/client.ts  (mock 内置知识 / 真实 LightRAG REST /query)
       └─ 产出 opencode 同构事件流：
            tool(running) → tool(completed, output=JSON 字符串) → message.part.delta(text)* → session.idle
  └─ qaEventSynthesizer  消费事件 → qa_token / qa_trace / qa_evidence
```

`driver/types.ts` 的事件形状严格对齐 opencode SDK `client.event.subscribe()`
（`cli/run/types.ts:53-109`、`event-handlers.ts:158-231`），所以**驱动可替换、消费层零改动**。

## 切换到真实 LightRAG / opencode

- **真实 LightRAG（仍走 mock 驱动）**：设 `LIGHTRAG_ENDPOINT`（并令 `LIGHTRAG_MOCK!=true`），
  `lightrag/client.ts` 即改走 REST `/query`。当前已兼容 LightRAG 0312+ 常见契约
  `{"response","references":[]}`，并支持 `LIGHTRAG_API_KEY_HEADER`、`LIGHTRAG_QUERY_MODE`
  （默认 `mix`）、`LIGHTRAG_TIMEOUT_MS`、`LIGHTRAG_INCLUDE_CHUNK_CONTENT`。
- **真实 opencode 常驻 server**：新增 `driver/opencode-driver.ts`（`createOpencode` +
  `session.promptAsync({agent: taiyi, tools:{question:false}})` + `event.subscribe`），
  在 `driver/index.ts` 按配置切换；agent 用 `qa-agent.ts` 的 `createTaiyiAgent`，
  LightRAG 经原生工具 `lightrag_query`（`src/witty/tools/lightrag/`）直接对接 REST `/query`，
  在 `plugin/tool-registry.ts` 全局注册。HTTP/合成/落库层无需改动。

## 只读与安全

- QA agent 经 allowlist 收敛为**仅检索类工具**：`lightrag*` 始终允许；`websearch*` / `webfetch`
  默认允许（`createTaiyiAgent` 的 `enableWebSearch`，默认 true），但仅当平台配置了 websearch MCP 时
  才真正注入——未配置即自动只走知识库。无 bash/编辑/修复能力（`qa-agent.ts`）。
- `lightrag_query` 工具 **lazy 连接**：仅在被调用时才发请求，端点不可达/超时只返回结构化 error、
  不抛不崩，不阻塞其它 agent（BC-006/NFR-001/S-007）。
- 端点/凭据经 env 注入（`LIGHTRAG_ENDPOINT` / `LIGHTRAG_API_KEY` 等），不入库、不打印（NFR-004）。
