# src/witty — 净室重写插件（Clean-Room Rewrite）

本目录是 witty-diagnosis-agent 的**净室重写**插件树，用于替代 `src/opencode/`（fork 自
SUL-1.0 许可的 oh-my-openagent，禁止商业分发）。

## 净室边界（NON-NEGOTIABLE）

1. 本目录下**禁止**从 `src/opencode/` 复制任何代码行（唯二例外见第 2 条）。
2. 允许迁移的只有两类**原创资产**：
   - 7 个诊断 agent 的**提示词文本**（抽取为 `agents/prompts/*.md` 纯数据文件）；
   - `tools/report-visualization` 与 `tools/lightrag` 的原创实现。
3. 仅依赖 MIT 许可的官方 SDK：`@opencode-ai/plugin`、`@opencode-ai/sdk`、`zod`、
   `jsonc-parser`、`commander`。禁止引入 `@code-yeongyu/*`、`@ast-grep/*`。
4. 功能取舍以《方案B-净室重写范围评估-完整文件清单.md》为准：只实现诊断产品需要的
   6 个模块，不复刻上游的通用 harness 能力。

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
├── tools/                    # 原创工具迁移落位
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

## 切换状态（旧树下线）

- [x] 本树各模块实现完成，插件与 web 功能经端到端验证；
- [x] `tsup.config.ts` 入口切到 `src/witty/{index,cli/index}.ts`，产物为 `dist/index.js` + `dist/cli.js`；
- [x] `install.sh` 只安装本树，旧链路已移除；
- [x] `script/build-schema-document.ts` 改用本树 `config/schema`，schema 已重新生成；
- [x] Web 前后端迁入 `src/witty/web/`（自包含，不依赖旧树）；
- [ ] 整体删除 `src/opencode/`（当前仅作参考保留，见其 `DEPRECATED.md`）；
- [ ] 按范围评估文档 E 类清单修正 LICENSE / package.json 依赖裁剪。
