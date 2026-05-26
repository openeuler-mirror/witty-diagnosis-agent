# witty-diagnosis-agent 项目索引

## 根目录文件

- **[README.md](./README.md)** - 项目介绍、安装与使用方法
- **[package.json](./package.json)** - npm 包配置
- **[tsconfig.json](./tsconfig.json)** - TypeScript 配置
- **[tsup.config.ts](./tsup.config.ts)** - 构建工具配置
- **[.env.example](./.env.example)** - 环境变量示例
- **[LICENSE](./LICENSE)** - 许可证
- **[test-spawn.ts](./test-spawn.ts)** - 测试文件

## 源码目录 (src/)

### 核心入口

- **[src/index.ts](./src/index.ts)** - 插件主入口

### Agent 层

- **[src/AGENTS.md](./src/AGENTS.md)** - Agent 角色定义

### Agent 实现

- **[src/agents/](./src/agents/)** - Agent 具体实现（含 21 个子模块）

### CLI 命令行

- **[src/cli/](./src/cli/)** - CLI 命令实现（含 30 个子模块）

### 插件系统

- **[src/plugin/](./src/plugin/)** - OpenCode 插件系统实现
- **[src/plugin-handlers/](./src/plugin-handlers/)** - 插件处理器
- **[src/plugin-interface.ts](./src/plugin-interface.ts)** - 插件接口定义
- **[src/plugin-config.ts](./src/plugin-config.ts)** - 插件配置管理
- **[src/plugin-state.ts](./src/plugin-state.ts)** - 插件状态管理

### 工具模块

- **[src/tools/](./src/tools/)** - 工具集合
  - `ast-grep/` - AST 代码搜索工具
  - `background-task/` - 后台任务管理
  - `interactive-bash/` - 交互式 Bash/Tmux 工具

### Hook 系统

- **[src/hooks/](./src/hooks/)** - Hook 系统实现
- **[src/create-hooks.ts](./src/create-hooks.ts)** - Hook 创建逻辑

### 配置管理

- **[src/config/](./src/config/)** - 配置管理模块
- **[src/create-tools.ts](./src/create-tools.ts)** - 工具创建逻辑
- **[src/create-managers.ts](./src/create-managers.ts)** - 管理器创建逻辑

### 功能模块

- **[src/features/](./src/features/)** - 功能模块（含 22 个子模块）

### MCP 服务

- **[src/mcp/](./src/mcp/)** - MCP (Model Context Protocol) 服务实现

### 共享模块

- **[src/shared/](./src/shared/)** - 共享工具与类型定义

### 测试

- **[src/index.test.ts](./src/index.test.ts)** - 入口测试
- **[src/index.compaction-model-agnostic.static.test.ts](./src/index.compaction-model-agnostic.static.test.ts)** - 静态测试

## 诊断技能 (skills/)

### 内核崩溃诊断

- **[skills/vmcore-analysis/](./skills/vmcore-analysis/)** - VMCore 内核崩溃分析
  - `SKILL.md` - 技能定义
  - `references/` - 参考文档（troubleshooting、source_code_structure、struct_analysis、crash_commands、root_cause_analysis、analysis_patterns）

### 磁盘诊断

- **[skills/disk-diagnosis-by-log/](./skills/disk-diagnosis-by-log/)** - 磁盘故障日志分析
  - `SKILL.md` - 技能定义
  - `references/` - 厂商 IBMC 参考（huawei、Inspur、h3c）、infocollect_guide

### 网络诊断

- **[skills/network-diagnosis/](./skills/network-diagnosis/)** - 网络故障诊断
  - `SKILL.md` - 技能定义
  - `scripts/README.md` - 脚本说明
  - `references/` - 防火墙指南

### OOM 诊断

- **[skills/linux-oom-analyzer/](./skills/linux-oom-analyzer/)** - 内存溢出 (OOM) 分析
  - `SKILL.md` - 技能定义
  - `references/` - 内核/系统/进程/CGroup OOM 分析

### 根因分析

- **[skills/root-cause-analysis/](./skills/root-cause-analysis/)** - 根因分析
  - `SKILL.md` - 技能定义
  - `examples/` - 分析示例
  - `tests/` - 测试用例

### 根因定界

- **[skills/root-cause-localization/](./skills/root-cause-localization/)** - 根因定位
  - `SKILL.md` - 技能定义

## 文档 (docs/)

### 概览

- **[docs/overview.md](./docs/overview.md)** - 文档概览与导航

### 使用指南

- **[docs/guide/MANUAL.md](./docs/guide/MANUAL.md)** - 用户手册
- **[docs/guide/INSTALLATION.md](./docs/guide/INSTALLATION.md)** - 安装指南
- **[docs/guide/CONTRIBUTING.md](./docs/guide/CONTRIBUTING.md)** - 贡献指南

### 参考文档

- **[docs/reference/development_framework_architecture.md](./docs/reference/development_framework_architecture.md)** - 开发框架架构
- **[docs/reference/agent-usage.md](./docs/reference/agent-usage.md)** - Agent 使用手册
- **[docs/reference/features.md](./docs/reference/features.md)** - 功能列表
- **[docs/reference/cli.md](./docs/reference/cli.md)** - CLI 手册
- **[docs/reference/configuration.md](./docs/reference/configuration.md)** - 配置参考

### 设计标准

- **[docs/standards/skill-interfaces.md](./docs/standards/skill-interfaces.md)** - Skill 接口规范
- **[docs/standards/ops-skills-spec.md](./docs/standards/ops-skills-spec.md)** - 运维 Skills 规范
- **[docs/standards/skill-documentation-format.md](./docs/standards/skill-documentation-format.md)** - Skill 文档格式
- **[docs/standards/data-formats.md](./docs/standards/data-formats.md)** - 数据格式定义
- **[docs/standards/commands.md](./docs/standards/commands.md)** - 命令规范
- **[docs/standards/configuration-formats.md](./docs/standards/configuration-formats.md)** - 配置格式规范

### 路线图

- **[docs/roadmap/ROADMAP-v0.1.0-2024Q2.md](./docs/roadmap/ROADMAP-v0.1.0-2024Q2.md)** - v0.1.0 迭代计划

### 故障排查

- **[docs/troubleshooting/opencode.md](./docs/troubleshooting/opencode.md)** - OpenCode 常见问题

## 资产 (assets/)

- **[assets/witty-diagnosis-agent.schema.json](./assets/witty-diagnosis-agent.schema.json)** - 配置 JSON Schema

## 配置 (config/)

- **[config/global.yaml](./config/global.yaml)** - 全局配置

## Ansible 剧本

- **[ansible/README.md](./ansible/README.md)** - Ansible 使用说明

## 脚本 (script/)

- **[script/build-schema.ts](./script/build-schema.ts)** - Schema 构建脚本
- **[script/build-binaries.js](./script/build-binaries.js)** - 二进制构建脚本
- **[script/build-schema-document.ts](./script/build-schema-document.ts)** - Schema 文档构建
- **[script/tsconfig.json](./script/tsconfig.json)** - 脚本 TypeScript 配置

## Agent 定义 (agents/)

- **[agents/diagnosis-agent.md](./agents/diagnosis-agent.md)** - 诊断 Agent 定义

## 命令定义 (commands/)

- **[commands/diagnose.md](./commands/diagnose.md)** - 诊断命令定义
- **[commands/collect-data.md](./commands/collect-data.md)** - 数据收集命令定义

## 钩子配置 (hooks/)

- **[hooks/hooks.json](./hooks/hooks.json)** - Hook 配置

## OpenCode 插件配置 (.opencode/)

- **[.opencode/INSTALL.md](./.opencode/INSTALL.md)** - OpenCode 安装说明
- **[.opencode/package.json](./.opencode/package.json)** - 插件包配置
- **[.opencode/plugins/witty-diagnosis-agent.js](./.opencode/plugins/witty-diagnosis-agent.js)** - 插件入口

## Codex 配置 (.codex/)

- **[.codex/INSTALL.md](./.codex/INSTALL.md)** - Codex 安装说明
- **[.codex/witty-diagnosis-agent-bootstrap.md](./.codex/witty-diagnosis-agent-bootstrap.md)** - Bootstrap 脚本

## 测试 (test/)

- **[test/install.test.ts](./test/install.test.ts)** - 安装测试
