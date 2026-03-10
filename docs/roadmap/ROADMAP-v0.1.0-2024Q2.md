# Roadmap v0.1.0 (2024 Q2)

**Theme**: 基础框架搭建与核心流程跑通 (Foundation & MVP)

本迭代旨在构建 Witty Diagnosis Agent 的最小可行性产品 (MVP)，实现从用户输入到诊断报告生成的完整闭环。

## 🎯 核心目标 (Goals)

- [ ] **Agent 协同框架**: 实现 Fuxi, Dayu, Kuafu, Baize 的基础通信与状态流转。
- [ ] **双模运行机制**: 支持“分阶段交互”与“全自动”两种模式的切换。
- [ ] **基础诊断能力**: 覆盖 CPU、内存、网络连通性等 Top 5 高频故障场景。

## 📅 详细规划 (Detailed Plan)

### 1. 核心架构 (Core Architecture)
> 负责人: @Xuanyuan | 状态: 🚧 In Progress

- [ ] **[Feat] 轩辕总控状态机实现** #101
  - *能力*: 实现 Phase 1-4 的状态流转与异常捕获。
  - *验收*: 单元测试覆盖率 > 80%。
- [ ] **[Feat] 统一上下文 (Context) 设计** #102
  - *能力*: 定义 Plan, Task, Report 的标准 JSON Schema。

### 2. 诊断规划 (Phase 1 - Fuxi)
> 负责人: @Fuxi | 状态: 📝 Todo

- [ ] **[Feat] 交互式信息收集** #110
  - *能力*: 识别用户意图，反问缺失的关键信息（如 IP、时间）。
- [ ] **[Feat] 诊断方案生成 (Plan Generation)** #111
  - *能力*: 基于故障现象生成包含 `Checklist` 的 Markdown 方案。

### 3. 执行与编排 (Phase 2 - Dayu & Kuafu)
> 负责人: @Dayu | 状态: 📝 Todo

- [ ] **[Feat] 任务拆解与并发调度** #120
  - *能力*: 将 Plan 拆解为多个 Task，分发给 Kuafu 执行。
- [ ] **[Feat] 基础 SSH 执行器** #121
  - *能力*: 安全地在目标主机执行只读命令 (Read-only)。

### 4. 分析与报告 (Phase 3 - Baize)
> 负责人: @Baize | 状态: 📝 Todo

- [ ] **[Feat] 根因分析 Prompt 调优** #130
  - *能力*: 基于采集数据生成逻辑严密的根因推断。
- [ ] **[Feat] 报告渲染引擎** #131
  - *能力*: 生成包含图表和高亮代码块的 Markdown 报告。

## 🚀 能力交付 (Capabilities Delivered)

| 功能模块 | 交付能力描述 | 对应 Issue |
| :--- | :--- | :--- |
| **CLI** | 支持 `witty start` 和 `witty diagnose <query>` 命令 | #100 |
| **Skill** | 内置 `check_cpu`, `check_mem`, `check_ping` 基础技能 | #122 |
| **Doc** | 完成 `INSTALLATION.md` 和 `USAGE.md` | #140 |

## 🔗 相关链接 (Links)

- [Kanban Board](https://github.com/orgs/Tech1024Wizard/projects/1)
- [Design Doc](../reference/development_framework_architecture.md)
