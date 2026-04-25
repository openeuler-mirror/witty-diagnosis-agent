# 安装与配置 (Installation & Configuration)

## 环境要求

- 运行环境：Node.js (>=20.0.0)
- 依赖工具：已安装[OpenCode](https://opencode.ai/)
- 依赖工具：已安装 [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/)（`ansible` 命令须在系统 PATH 中可用，可通过 `ansible --version` 提前验证）

## 安装

智能诊断Agent支持**在线安装**与**源码安装**两种方式，您可根据自身网络环境与使用需求选择合适方式。

### 方式一：在线安装（推荐）

通过 npm 全局安装智能诊断 Agent，安装完成后可通过命令行一键为 OpenCode 注册插件及配置：

```bash
npm install -g witty-diagnosis-agent@latest
witty-diagnosis-agent install
```

### 方式二：源码安装

如果您需要二次开发或在离线环境中使用，可以使用一键安装脚本自动完成环境检查、依赖安装、项目构建及插件配置：

```shell
git clone https://atomgit.com/openeuler/witty-diagnosis-agent.git
cd witty-diagnosis-agent
bash install.sh
```

## 配置

修改项目根目录下的`.opencode/witty-diagnosis-agent.jsonc` 文件，为各个Agent配置缺省运行模型，以下以 `deepseek/deepseek-chat` 模型为例（可根据实际需求替换）：

```json
{
  "agents": {
    "fuxi":  { "model": "deepseek/deepseek-chat" },
    "dayu":  { "model": "deepseek/deepseek-chat" },
    "kuafu": { "model": "deepseek/deepseek-chat" },
    "baize": { "model": "deepseek/deepseek-chat" }
  }
}
```

## 常见问题 (Troubleshooting)

如果在安装过程中遇到问题，请检查以下几点：

- **Node.js 版本**：确保 Node.js 版本 >= 18.0.0。
- **权限问题**：如果在 Linux/macOS 上遇到权限错误，尝试使用 `sudo` 或检查目录权限。
- **网络代理**：如果处于内部网络，请确保配置了正确的 npm 代理。

更多问题排查请参考：[Troubleshooting](../troubleshooting/troubleshooting.md)
