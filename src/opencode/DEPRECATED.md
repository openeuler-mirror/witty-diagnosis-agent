# ⚠️ 本目录已停用（DEPRECATED）· 仅作参考

**本目录不参与构建、不参与安装、不是运行中的实现。**

现行实现在 **[`src/witty/`](../witty/)**（净室重写树）：

| 用途 | 现行位置 |
|---|---|
| 插件源码 | `src/witty/` |
| 构建入口 | `tsup.config.ts` → `src/witty/index.ts` + `src/witty/cli/index.ts` |
| 构建产物 | `dist/index.js` + `dist/cli.js` |
| Web 前后端 | `src/witty/web/` |
| 安装 | 仓库根 `bash install.sh` |

## 为什么保留

本目录（连同其 `web/`）是重构前的实现，保留用于**查阅历史实现细节与设计意图**。
它 fork 自 `oh-my-openagent`，受 **Sustainable Use License 1.0** 约束，禁止商业分发；
净室重写正是为消除该约束而做。待净室版本稳定后本目录将被整体删除。

## 常见误操作

- ❌ 在本目录执行 `bash web/init.sh` 或 `bash web/start.sh`
  → ✅ 请到 `src/witty/web/` 下执行（本目录的 `node_modules` 可能与当前 Node 版本不匹配）
- ❌ 修改本目录代码期望生效
  → ✅ 改动请落在 `src/witty/`，本目录的任何修改都不会进入构建产物
