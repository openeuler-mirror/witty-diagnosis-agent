# 运维 Skills 定义规范 (Ops Skills Definition Standard)

本规范定义了在 witty-diagnosis-agent 中开发和集成运维场景 Skills 的标准。旨在确保 Skills 的安全性、可观测性及可复用性。

## 1. Skill 分类 (Categories)

为便于管理和调度，所有运维 Skills 必须归属于以下分类之一：

| 分类 | 标识符 | 说明 | 典型示例 | 权限要求 |
| :--- | :--- | :--- | :--- | :--- |
| **信息收集** | `collection` | 只读操作，获取系统状态、日志、配置 | `get-cpu-usage`, `read-log`, `check-port` | 低 (Read-Only) |
| **诊断分析** | `analysis` | 对收集的数据进行计算、聚合或模式识别 | `analyze-log-pattern`, `calculate-error-rate` | 无 (本地计算) |
| **主动探测** | `probe` | 发起网络请求、模拟用户行为以验证服务可用性 | `http-ping`, `tcp-connect`, `dns-lookup` | 中 (Network Access) |
| **修复执行** | `remediation` | 修改系统状态、重启服务、变更配置 | `restart-service`, `scale-pod`, `modify-config` | 高 (Write/Execute) |

## 2. 元数据规范 (Metadata)

每个 Skill 的 Markdown 文件头部必须包含以下 YAML Frontmatter：

```yaml
---
name: service-restart              # [必填] Skill 唯一标识符，使用 kebab-case
version: 1.0.0                     # [必填] 语义化版本号
description: Restart a systemd service safely # [必填] 功能简述
category: remediation              # [必填] 所属分类
author: ops-team                   # [选填] 维护团队
risk_level: high                   # [必填] 风险等级: low, medium, high
permissions:                       # [必填] 所需权限声明
  - sudo
  - systemctl
tags:                              # [选填] 用于搜索和过滤
  - systemd
  - recovery
---
```

## 3. 输入/输出规范 (I/O Schema)

为了保证 Agent 能准确调用，Skill 必须明确定义输入参数和输出结构。

### 3.1 输入定义
在文档的 `## Arguments` 章节中使用表格定义：

| 参数名 | 类型 | 必填 | 默认值 | 说明 |
| :--- | :--- | :--- | :--- | :--- |
| `service_name` | string | 是 | - | 目标服务名称 (如 nginx) |
| `force` | boolean | 否 | false | 是否强制重启 |

### 3.2 输出定义
在文档的 `## Output` 章节描述返回的 JSON 结构：

```json
{
  "status": "success",     // success | failed
  "message": "Service nginx restarted successfully",
  "data": {
    "pid": 12345,
    "start_time": "2023-10-27T10:00:00Z"
  }
}
```

## 4. 安全规范 (Security)

运维操作涉及系统稳定性，必须遵循以下安全准则：

1.  **最小权限原则**：Skill 内部实现的命令应仅限于完成任务所需的最小权限。避免直接使用 `rm -rf` 等高危命令。
2.  **参数校验**：必须对输入参数进行严格校验，防止命令注入（如禁止参数中包含 `;`, `|`, `&` 等特殊字符）。
3.  **二次确认**：对于 `risk_level: high` 的 Skill（如重启、删除），Agent 在调用前必须向用户发起确认请求。
4.  **操作审计**：所有 `remediation` 类 Skill 的执行日志必须持久化保存，包含调用者、时间、参数及结果。

## 5. 编写模板 (Template)

请复制以下模板开发新的运维 Skill：

```markdown
---
name: my-ops-skill
version: 0.1.0
description: Description of what this skill does
category: collection
risk_level: low
---

# Instruction

详细描述 Skill 的功能和使用场景。Agent 将根据此描述决定是否调用该 Skill。

## Arguments

| Name | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `target` | string | true | The target IP or hostname |

## Implementation

此处编写具体的执行逻辑（可以是 Shell 脚本、Python 代码或 MCP 调用）。

\`\`\`bash
#!/bin/bash
# 示例实现
echo "Checking target: $target"
ping -c 4 $target
\`\`\`

## Error Handling

描述可能的错误码及其含义。
```

## 6. 最佳实践

- **原子性**：一个 Skill 只做一件事。复杂的任务应通过 Agent 编排多个原子 Skill 来完成。
- **幂等性**：修复类 Skill 应尽可能设计为幂等的（即多次执行效果相同），以应对网络重试。
- **无状态**：Skill 不应依赖本地内存状态，所有上下文应通过参数传递。
