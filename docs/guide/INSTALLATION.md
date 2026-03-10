# 安装 (Installation)

witty-diagnosis-agent 支持多种安装方式，以适应不同的网络环境和使用场景。

## 在线安装 (Online Installation)

如果您的环境可以连接外网，这是最简单快捷的安装方式。

### 方式 1: 使用 Agent 自动化安装 (推荐)

直接将安装指令发送给 OpenCode Agent，让其自动完成下载与配置。详情请参考：
- [自动化安装指南](../witty-diagnosis-installation.md)

### 方式 2: 使用包管理器安装

如果您熟悉命令行操作，可以直接通过 npm 或 bun 进行安装：

```bash
# 使用 npm
npm install -g witty-diagnosis-agent

# 使用 bun
bun add -g witty-diagnosis-agent
```

安装完成后，运行以下命令验证：

```bash
witty-diagnosis-agent -V
```

## 离线安装 (Offline Installation)

适用于内网环境或无法直接连接 npm 仓库的服务器。

### 方式 1: 离线包安装 (待补充)

> **注意**：目前离线安装包正在构建中，后续将提供 `.tar.gz` 或 `.zip` 格式的离线包下载链接。

**预期步骤**：
1. 在有网环境下载离线安装包。
2. 将安装包传输至目标服务器。
3. 解压并执行安装脚本。

```bash
# 示例命令 (待实现)
tar -zxvf witty-diagnosis-agent-offline.tar.gz
cd witty-diagnosis-agent
./install.sh
```

### 方式 2: 源码编译安装

如果无法获取离线包，您可以在有网环境下载源码及依赖，然后打包传输至离线环境进行编译安装。

#### 1. 准备源码 (有网环境)

```bash
# 克隆仓库
git clone https://atomgit.com/Tech1024Wizard/witty-diagnosis-agent.git
cd witty-diagnosis-agent

# 安装依赖 (生成 node_modules)
bun install
# 或者
npm install
```

#### 2. 打包源码 (有网环境)

将包含 `node_modules` 的整个目录打包：

```bash
tar -zcvf witty-diagnosis-agent-source.tar.gz witty-diagnosis-agent/
```

#### 3. 传输与安装 (离线环境)

将 `witty-diagnosis-agent-source.tar.gz` 上传至离线服务器，解压并构建：

```bash
# 解压源码
tar -zxvf witty-diagnosis-agent-source.tar.gz
cd witty-diagnosis-agent

# 构建插件
bun run build
# 或者
npm run build

# 链接到全局 (可选)
npm link
# 或者直接运行 bin 目录下的脚本
./bin/witty-diagnosis-agent.js install
```

## 常见问题 (Troubleshooting)

如果在安装过程中遇到问题，请检查以下几点：

- **Node.js 版本**：确保 Node.js 版本 >= 18.0.0。
- **权限问题**：如果在 Linux/macOS 上遇到权限错误，尝试使用 `sudo` 或检查目录权限。
- **网络代理**：如果处于公司内网，请确保配置了正确的 npm 代理。

更多问题排查请参考：[Troubleshooting](../troubleshooting/opencode.md)
