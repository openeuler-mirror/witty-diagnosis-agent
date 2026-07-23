# agents/prompts — 提示词纯数据

每个诊断 agent 一个 `<name>.md`，由 `prompt-loader.ts` 在注册时加载。

## 迁移规则（净室边界内允许的唯一提示词来源）

提示词内容从旧树 `src/opencode/agents/<name>/` 中**只抽取原创中文诊断文本**：

| 目标文件 | 旧树来源（仅抽原创提示词文本） |
|---|---|
| xuanyuan.md | src/opencode/agents/xuanyuan/{system-prompt,identity-constraints,behavioral-summary}.ts 内的字符串 |
| fuxi.md | src/opencode/agents/fuxi/fuxi/、fuxi-sub/ 内的字符串 |
| dayu.md | src/opencode/agents/dayu/{system-prompt,identity-constraints,interview-mode,behavioral-summary}.ts 内的字符串 |
| kuafu.md | src/opencode/agents/kuafu/{agent,prompt-section-builder}.ts 内的字符串 |
| baize.md | src/opencode/agents/baize/index.ts 内的字符串 |
| nuwa.md | src/opencode/agents/nuwa/agent.ts 内的字符串 |
| taiyi.md | src/opencode/agents/taiyi/qa-agent.ts 内的字符串 |

**禁止**带入的上游内容（这些是 oh-my-openagent 的英文骨架提示词，不是原创）：

- "Task Discipline (NON-NEGOTIABLE)"、todo/task 纪律段落；
- 任何包含 sisyphus / prometheus / atlas / ultrawork / boulder 字样的段落；
- 上游的工具使用说明模板（categorizeTools 生成段落）。

抽取后逐文件人工复核：只保留诊断领域逻辑（现象澄清、计划模板、证据链要求、
报告结构、修复三级方案等），措辞如有上游痕迹一律重写。

## 占位符

| 占位符 | 含义 |
|---|---|
| `{{PROJECT_DIR}}` | 当前项目目录 |
| `{{REPORT_DIR}}` | 报告输出目录（config.report.output_dir） |
