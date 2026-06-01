# xiaoO 适配层（占位）

本目录是诊断 agent 在 **xiaoO 框架**下的适配实现，与 [`../opencode/`](../opencode/) 平行。

## 与 opencode 适配层的区别

| | `src/opencode/` | `src/xiaoO/`（本目录） |
|---|---|---|
| 形态 | opencode 插件，TS/JS 代码 | **配置驱动，以 JSON 为主** |
| 接入方式 | 实现 opencode 的 `Plugin` 钩子接口 | 拷贝/加载 JSON 配置 |
| 与 opencode | 完全不兼容（异构） | 完全不兼容（异构） |

两个适配层之间**没有共享代码**：一边是 JS 逻辑，一边是 JSON 配置。

## 共享的领域内容

两个框架真正复用的是仓库顶层的 [`skills/`](../../skills/) —— 诊断技能（Markdown + 脚本），语言/框架无关。本目录的配置应**引用**顶层 `skills/`，而非拷贝一份。

## 现状

占位阶段，尚未实现。后续把 xiaoO 所需的 JSON 配置放入 [`config/`](config/) 即可（大部分可直接拷贝）。
