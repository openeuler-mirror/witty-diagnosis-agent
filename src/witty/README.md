# src/witty — 插件实现

本目录是 witty-diagnosis-agent 的插件实现，为本项目的唯一实现树。

**本项目以木兰宽松许可证第2版（Mulan PSL v2）开源**，见仓库根目录 `LICENSE`。

## 工程约束（NON-NEGOTIABLE）

1. 本目录下的代码均为原创实现。
2. 提示词一律以纯数据形式存放于 `agents/prompts/*.md`，不内联进 TS 定义文件。
3. 仅依赖宽松许可的官方 SDK：`@opencode-ai/plugin`、`@opencode-ai/sdk`、`zod`、
   `jsonc-parser`、`commander`。新增依赖须为宽松许可，不得引入与 Mulan PSL v2
   冲突的 copyleft 或商用限制条款。
4. 范围限定：只实现诊断产品需要的 6 个模块，不复刻通用 harness 能力。

## 目录结构

```
src/witty/
├── index.ts                  # 插件入口（OpenCode Plugin 签名）
├── plugin.ts                 # 装配器：组合 config/agents/skills/guards/tools → Hooks
├── config/                   # 模块1：配置加载（Zod + JSONC，~500 行）
│   ├── types.ts              #   配置类型（对外契约）
│   ├── schema.ts             #   Zod schema（生成 assets/*.schema.json 的唯一来源）
│   └── load.ts               #   项目/用户两级 JSONC 配置发现与合并
├── agents/                   # 模块2：Agent 注册器（~800 行）
│   ├── types.ts              #   AgentDefinition 契约
│   ├── registry.ts           #   定义 + 用户覆盖 → OpenCode Config.agent
│   ├── prompt-loader.ts      #   从 prompts/*.md 加载提示词（纯数据）
│   ├── definitions/          #   7 个诊断 agent 的注册定义
│   └── prompts/              #   迁移来的提示词纯数据（见其 README）
├── skills/                   # 模块3：技能发现与暴露（~600 行）
│   ├── types.ts
│   └── discovery.ts          #   扫描仓库顶层 skills/ + 经 OpenCode 原生 skill 机制暴露
├── orchestration/            # 模块4：诊断流水线编排（~1,500 行）
│   ├── types.ts              #   流水线阶段 / 子代理运行契约
│   ├── pipeline.ts           #   xuanyuan→fuxi→dayu→kuafu→baize→nuwa 阶段表
│   └── subagent-runner.ts    #   基于 OpenCode 原生 session API 的子代理薄层
├── guards/                   # 模块5：守护钩子（~600 行）
│   ├── md-only.ts            #   规划类 agent（fuxi/dayu）仅允许写 .md
│   ├── compaction-preserver.ts # 压缩时保留诊断上下文
│   ├── session-notifier.ts   #   会话完成/出错通知
│   └── output-truncator.ts   #   工具输出截断（防上下文爆炸）
├── tools/                    # 诊断工具
│   ├── report-visualization.ts
│   └── lightrag.ts
├── shared/                   # 基础工具（~400 行）
│   ├── log.ts
│   ├── jsonc.ts
│   └── paths.ts
└── cli/                      # 模块6：安装 CLI（~500 行）
    ├── index.ts              #   commander 入口（install / doctor）
    ├── install.ts            #   安装 skills + 写配置
    └── doctor.ts             #   环境自检（doctor-lite）
```

## 构建与安装

- `tsup.config.ts` 入口为 `src/witty/{index,cli/index}.ts`，产物为 `dist/index.js`（插件）
  与 `dist/cli.js`（安装 CLI）；`agents/prompts/` 随构建复制到 `dist/prompts/`。
- `script/build-schema-document.ts` 由 `config/schema` 生成配置 JSON Schema。
- Web 前后端位于 `src/witty/web/`，自包含。
