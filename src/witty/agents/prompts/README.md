# agents/prompts — 提示词纯数据

每个诊断 agent 一个 `<name>.md`，由 `prompt-loader.ts` 在注册时加载。

## 内容规范

提示词只写诊断领域逻辑：现象澄清、计划模板、证据链要求、报告结构、修复三级方案等。

- 每个 agent 提供中英两版：`<name>.md`（中文）与 `<name>.en.md`（英文），
  由 `prompt-loader.ts` 按配置的 `output_language` 选择，缺失时回退到 `<name>.md`。
- 不写通用 harness 纪律段落（todo/task 流程、工具使用说明模板等），
  这些由 OpenCode 自身提供，重复声明会与宿主指令冲突。
- agent 名一律使用当前注册名（xuanyuan / fuxi / dayu / kuafu / baize / nuwa / taiyi）。

## 占位符

| 占位符 | 含义 |
|---|---|
| `{{PROJECT_DIR}}` | 当前项目目录 |
| `{{REPORT_DIR}}` | 报告输出目录（config.report.output_dir） |
