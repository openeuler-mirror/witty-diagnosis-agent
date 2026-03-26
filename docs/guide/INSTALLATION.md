# 安装与配置 (Installation & Configuration)

Witty 智能诊断 Agent 支持多种安装方式，以适应不同的网络环境和使用场景。

## 在线安装 (Online Installation)

如果您的环境可以连接外网，这是最简单快捷的安装方式。

### 方式 1: 使用 npm 全局安装 (推荐)

通过 npm 全局安装 Witty 智能诊断 Agent，安装完成后可通过命令行一键为 witty-diagnosis-agent 注册插件及配置：

```bash
npm install -g witty-diagnosis-agent@latest
witty-diagnosis-agent install
```

安装完成后，运行以下命令验证：

```bash
witty-diagnosis-agent -V
```

### 方式 2: 使用 Agent 自动化安装

复制如下内容到 witty-diagnosis-agent 对话框，由 Agent 引导您完成安装：

```text
请根据这里的说明安装并配置 witty-diagnosis-agent：
https://atomgit.com/openeuler/witty-diagnosis-agent/blob/master/docs/reference/witty-diagnosis-installation.md
```

## 离线安装 (Offline Installation)

适用于内网环境或无法直接连接 npm 仓库的服务器。

### 方式 1: 源码编译安装

如果您需要二次开发或在离线环境中使用，可通过源码方式安装。

#### 1. 获取代码与依赖

```shell
git clone https://atomgit.com/openeuler/witty-diagnosis-agent.git
cd witty-diagnosis-agent
bun install
```

#### 2. 构建项目

```shell
bun run build
```

构建完成后，将在项目根目录生成 `dist/index.js` 等相关文件。

#### 3. 注册插件

配置文件支持两种路径（二选一），优先选择用户级配置：

- 用户级（推荐）：`~/.config/witty-diagnosis-agent/witty-diagnosis-agent.json` 或 `witty-diagnosis-agent.jsonc`
- 项目级：项目根目录下的 `.witty-diagnosis-agent/witty-diagnosis-agent.json` 或 `.witty-diagnosis-agent/witty-diagnosis-agent.jsonc`

在配置文件中新增或修改 `plugin` 数组，指向本仓库的构建入口（如果 `witty-diagnosis-agent.json` 文件不存在，请手动创建一个）：

```json
{
    "$schema": "https://witty-diagnosis-agent.ai/config.json",
    "plugin": [
        "file:///{witty-diagnosis-agent项目绝对路径}/dist/index.js"
    ]
}
```

示例（假设项目绝对路径为 `/opt/witty-diagnosis-agent`）：

```json
{
    "$schema": "https://witty-diagnosis-agent.ai/config.json",
    "plugin": [
        "file:///opt/witty-diagnosis-agent/dist/index.js"
    ]
}
```

## 常见问题 (Troubleshooting)

如果在安装过程中遇到问题，请检查以下几点：

- **Node.js 版本**：确保 Node.js 版本 >= 18.0.0。
- **权限问题**：如果在 Linux/macOS 上遇到权限错误，尝试使用 `sudo` 或检查目录权限。
- **网络代理**：如果处于公司内网，请确保配置了正确的 npm 代理。

更多问题排查请参考：[Troubleshooting](../troubleshooting/witty-diagnosis-agent.md)
