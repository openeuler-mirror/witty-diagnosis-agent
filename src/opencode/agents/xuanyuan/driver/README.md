# xuanyuan/driver · 故障运维诊断驱动层

故障运维（故障运维 / Ops）任务的「执行大脑」。web/server 的 `runner.ts` 经本目录把一次诊断任务
（在线/离线）跑成一条**任务域事件流**（阶段 / 日志 / 报告），自身只负责脱敏、落库、SSE 推送、
终态收敛——与驱动是 mock 还是真实 opencode 无关。设计依据见
`docs/design/intelligent-diagnosis-frontend-web-service/02-需求设计规格书.md`（D-001 / D-002）。

## 模块边界（重要）

为保证 `web/server` 的 `tsc --noEmit` 编译路径**零 `@opencode-ai/sdk` 依赖**（与 `agents/taiyi`
同约定），本目录分两类文件：

| 类别 | 文件 | 依赖 | 被 web/server 静态 import |
|---|---|---|---|
| **Web 可导入核心**（零外部依赖） | `index.ts`、`types.ts`、`mock-driver.ts`、`report-template.ts`、`event-synthesizer.ts` | 仅 node 内置 | ✅ 是 |
| **真实 opencode 路径** | `opencode-driver.ts` | `@opencode-ai/sdk` | ❌ 否（运行时动态 import） |

`index.ts` 的工厂只静态 import mock；`TASK_DRIVER=opencode` 时经**运行时动态 import**
（specifier 显式拓宽为 `string`，tsc 不跟随）加载 `opencode-driver.ts`。后者的类型检查由
`src/opencode` 根工程覆盖（根工程含 SDK）。

## 数据流

```
runner.ts (web/server)
  └─ createTaskDriver({ driver: "mock" | "opencode" })
       ├─ mock-driver       确定性阶段时序 → stage/log/report（HTML 由 report-template 生成）
       └─ opencode-driver   每任务 createOpencode（withWorkingOpencodePath 定位本项目 opencode）
            重定向 HOME 隔离每任务 agent 状态（D-001）；保留 XDG_DATA/CONFIG 以沿用凭据/配置
            session.create → event.subscribe → resolveAgentName() → promptAsync({agent, tools:{question:false}})
            └─ event-synthesizer  opencode 事件 → stage/log（forward-only 阶段推断 + 报告路径捕获）
            └─ 双信号完成（D-002）：主会话 busy→idle 稳定 或 baize/reports/*.html 落地 → 读取 HTML → emit report
```

`runner.ts` 据「是否产出 report」判定成功/失败；report HTML 脱敏后落库，前端 `HtmlReportView` 内嵌展示。

## 切到真实路径

1. 设 `TASK_DRIVER=opencode`，并配 `TASK_OPENCODE_BIN`（本项目 opencode 二进制绝对路径）。
   `TASK_MODEL` 可留空，沿用 opencode 已配置的默认模型/凭据。
2. 在线诊断会把 SSH 凭据前置注入首条 prompt（供 Kuafu 采集）；凭据仅内存保险箱驻留、终态即焚，
   日志/报告经 `desensitizeWith` 脱敏。
3. 端到端验证脚本：`scripts/task-live.sh`（真实 opencode 跑通 Fuxi→Dayu→Kuafu→Baize→报告全链路）。

### 实现要点（实测，opencode 1.14.x）

- **agent 名按运行时解析**：promptAsync 的 `agent` 必须匹配注册名（如 `Xuanyuan (Controller)`，**非**
  `xuanyuan`，否则 `Agent not found`）；`resolveAgentName` 经 `client.app.agents` 动态取名，跨构建稳健。
- **promptAsync 是 fire-and-forget**：提交即 resolve，**不能**当 turn 结束信号；完成以「主会话 busy→idle
  稳定」或「报告 HTML 落地」判定（`session.status.type` / `session.idle`），`session.error` 即失败。
- **凭据隔离取舍**：只重定向 `HOME`（隔离每任务 `~/.witty-diagnosis-agent/{dayu,kuafu,baize}`），
  **保留** `XDG_DATA_HOME`/`XDG_CONFIG_HOME` 指向真实用户目录，否则丢失 opencode 鉴权 → LLM 调用失败。

### 隔离限制（待办）

`createOpencode` 不支持 per-call env，HOME 重定向经 `process.env` 完成、以模块级互斥串行化
「改 env → 起 server」窗口；会话存储随真实 `XDG_DATA` 共享。**若需更强的多任务并发隔离**，应改为
每任务独立 node 进程 spawn（与 D-001 原意一致）。当前实现下务必将 `SCHEDULER_MAX_CONCURRENT=1`。

## 测试

- `event-synthesizer.test.ts`：阶段 forward-only 推断、按行日志、报告路径跨增量捕获（`node --test`）。
- `web/server/scripts/task-smoke.sh`：mock 驱动端到端（新建→SSE 执行流→HTML 报告→脱敏）。
