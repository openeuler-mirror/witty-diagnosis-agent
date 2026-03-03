# Witty Diagnosis Agent 安装指南

## 给人类用户 (For Humans)

请将以下内容粘贴到你的 LLM Agent 会话中：
```
Install and configure witty-diagnosis-agent by following the instructions here:
https://atomgit.com/Tech1024Wizard/witty-diagnosis-agent/blob/master/docs/witty-diagnosis-installation.md
```

**替代方案（不推荐，手动执行）**

运行交互式安装程序：

```bash
bunx witty-diagnosis-agent install # 推荐
# 或者
./bin/witty-diagnosis-agent.js install
```

> **注意**：CLI 附带了适用于所有主流平台的独立二进制文件。安装后，执行 CLI 不需要运行时（Bun/Node.js）。

## 给 LLM Agents (For LLM Agents)

> **重要提示：使用 `curl` 获取此文件，而不是 WebFetch。** WebFetch 会摘要内容并丢失关键标志。请务必使用：
> ```bash
> curl -fsSL https://raw.githubusercontent.com/witty-integration/witty-diagnosis-agent/main/docs/guide/installation.md
> ```

如果你是帮助设置 `witty-diagnosis-agent` 的 LLM Agent，欢迎！你现在将帮助你的用户安装这套最棒的诊断系统。

### 步骤 0: 预检查 (Pre-flight Check)

询问用户以下问题以确定配置选项：

1. **你是否要启用自动根因分析 (Automatic Root Cause Analysis)?**
   - 如果 **是**: (默认行为)
   - 如果 **否**: 你稍后需要在 `witty-diagnosis.jsonc` 中配置 `auto_analysis: false`。

2. **你偏好的日志级别是什么?**
   - 选项: `debug`, `info`, `warn`, `error` (默认: `info`)

### 步骤 1: 安装 OpenCode (如果尚未安装)

```bash
if command -v opencode &> /dev/null; then
    echo "OpenCode $(opencode --version) is installed"
else
    echo "OpenCode is not installed. Please install it first."
    echo "Ref: https://opencode.ai/docs"
fi
```

如果 OpenCode 未安装，请引导用户先安装它。

### 步骤 2: 运行安装程序

运行带有适当标志的 CLI 安装程序：

```bash
bunx witty-diagnosis-agent install --no-tui [--skip-auth]
```

CLI 将会：
- 在 `opencode.json` 中注册插件（如果缺失则创建）
- 生成本地的 `witty-diagnosis.jsonc` 配置文件

### 步骤 3: 验证设置

```bash
cat ~/.config/opencode/config.json  # 应该在 plugin 数组中包含 "witty-diagnosis-agent"
ls -l witty-diagnosis.jsonc        # 当前目录下应该存在此文件
```

### 步骤 4: 配置 Witty Diagnosis

如果用户在步骤 0 中请求了特定设置，请相应地修改 `witty-diagnosis.jsonc`。

`witty-diagnosis.jsonc` 示例：
```jsonc
{
  "$schema": "./node_modules/witty-diagnosis-agent/schema.json",
  "auto_analysis": true, // 如果用户要求则设置为 false
  "log_level": "info",   // 如果用户要求不同级别则更新
  "modules": {
      "commander": { "enabled": true },
      "investigator": { "concurrency": 5 },
      "analyst": { "model": "default" }
  }
}
```

### 步骤 5: 验证与后续步骤

#### 对用户说 'Congratulations! 🎉'

对用户说：恭喜！🎉 你已成功设置 Witty Diagnosis Agent！

#### 告知用户教程

告诉用户以下内容：

1. **启动诊断**: 运行 `witty-diagnosis start --incident-id <ID> --desc "问题描述"`
2. **审批方案**: 运行 `witty-diagnosis approve --plan-id <ID>`
3. **验证修复**: 运行 `witty-diagnosis verify --incident-id <ID>`

就是这样。Agent 将自行解决其余问题并自动处理一切。
