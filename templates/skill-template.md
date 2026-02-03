---
name: skill-template
description: 技能模板 - 用于创建新技能的模板文件
version: 1.0.0
category: template
author: witty-diagnosis-agent
created: 2026-02-03
updated: 2026-02-03
tags:
  - template
  - documentation
  - skill-development
---

# [技能名称] - [人类可读的技能名称]

<!--
提示：将方括号中的内容替换为实际值
-->

## 概述

<!--
简要介绍技能的目的、功能和适用场景。
说明技能在整个诊断流程中的位置和作用。

示例：
本技能用于收集系统运行数据，包括日志、指标和配置信息。
它是诊断流程的第一步，为后续分析提供数据基础。
-->

[在此处填写技能概述]

## 使用时机

<!--
明确说明何时应该使用此技能，包括：
- 典型的触发条件
- 预期的输入状态
- 与其他技能的配合关系

示例：
- 当需要收集系统数据进行分析时
- 作为诊断流程的初始步骤
- 与其他分析技能配合使用
-->

### 应该使用此技能的情况：
- [情况1]
- [情况2]
- [情况3]

### 不应该使用此技能的情况：
- [情况1]
- [情况2]

## 输入要求

### 必需输入

<!--
描述技能执行必需的数据和参数
-->

| 参数名 | 类型 | 描述 | 示例值 |
|--------|------|------|--------|
| `session_id` | string | 诊断会话ID | `"diagnosis-123"` |
| `target` | string | 诊断目标 | `"system"`, `"network"`, `"storage"`, `"security"` |
| [参数1] | [类型] | [描述] | [示例值] |
| [参数2] | [类型] | [描述] | [示例值] |

### 可选输入

<!--
描述可选的配置参数和默认值
-->

| 参数名 | 类型 | 默认值 | 描述 |
|--------|------|--------|------|
| `timeout` | number | `300` | 执行超时时间（秒） |
| `verbosity` | string | `"info"` | 日志详细程度：`"debug"`, `"info"`, `"warn"`, `"error"` |
| [参数1] | [类型] | [默认值] | [描述] |

### 输入格式示例

```json
{
  "session_id": "diagnosis-session-001",
  "target": "system",
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    // 添加技能特定的参数
  },
  "metadata": {
    "request_id": "req-001",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

## 执行步骤

<!--
详细描述技能的执行流程，每个步骤应包含具体操作和使用的工具方法
-->

### 1. 初始化阶段
- 验证输入参数
- 初始化日志记录
- 准备执行环境

### 2. 数据收集/处理阶段
- [步骤1描述]
- [步骤2描述]
- [步骤3描述]

### 3. 分析/计算阶段
- [步骤1描述]
- [步骤2描述]

### 4. 结果生成阶段
- 格式化输出结果
- 收集执行指标
- 清理临时资源

## 输出格式

### 成功输出格式

```json
{
  "status": "success",
  "session_id": "diagnosis-session-001",
  "execution_time": 123.45,
  "results": {
    // 技能特定的结果数据
    // 示例：
    "data_collected": true,
    "metrics": {
      "cpu_usage": 45.2,
      "memory_usage": 67.8
    },
    "issues_found": 2,
    "severity": "warning"
  },
  "metadata": {
    "skill_name": "[技能名称]",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z",
    "execution_mode": "standard"
  }
}
```

### 错误输出格式

```json
{
  "status": "error",
  "session_id": "diagnosis-session-001",
  "error_code": "[ERROR_CODE]",
  "error_message": "人类可读的错误描述",
  "details": {
    "failed_step": "[失败步骤]",
    "error_context": {
      // 详细的错误上下文信息
    }
  },
  "suggestions": [
    "可能的修复建议1",
    "可能的修复建议2"
  ],
  "metadata": {
    "skill_name": "[技能名称]",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

### 输出字段说明

| 字段名 | 类型 | 必需 | 描述 |
|--------|------|------|------|
| `status` | string | 是 | 执行状态：`"success"`, `"error"`, `"partial"` |
| `session_id` | string | 是 | 诊断会话ID |
| `execution_time` | number | 是 | 执行时间（秒） |
| `results` | object | 是 | 技能特定的结果数据 |
| `metadata` | object | 是 | 元数据信息 |
| `error_code` | string | 否 | 错误代码（仅错误时） |
| `error_message` | string | 否 | 错误描述（仅错误时） |
| `details` | object | 否 | 详细错误信息（仅错误时） |
| `suggestions` | array | 否 | 修复建议（仅错误时） |

## 示例

### 示例1：基础使用

**场景描述**：
[简要描述示例场景]

**命令调用**：
```bash
claude witty-diagnosis:[技能名称] --target system --timeout 300
```

**输入数据**：
```json
{
  "session_id": "example-session-001",
  "target": "system",
  "parameters": {
    "timeout": 300,
    "verbosity": "info"
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "example-session-001",
  "execution_time": 45.2,
  "results": {
    // 技能特定的成功结果
  },
  "metadata": {
    "skill_name": "[技能名称]",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

### 示例2：高级场景

**场景描述**：
[描述更复杂的用例]

**命令调用**：
```bash
claude witty-diagnosis:[技能名称] --target network --custom-param value --output-format json
```

**输入数据**：
```json
{
  "session_id": "advanced-session-001",
  "target": "network",
  "parameters": {
    "custom_param": "value",
    "output_format": "json",
    "detailed_analysis": true
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "advanced-session-001",
  "execution_time": 120.5,
  "results": {
    // 详细的技能结果
  },
  "metadata": {
    "skill_name": "[技能名称]",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z",
    "analysis_mode": "detailed"
  }
}
```

## 注意事项

### 安全注意事项
<!--
描述安全相关注意事项
-->
- [权限要求]
- [数据敏感性]
- [操作风险]

### 性能注意事项
<!--
描述性能相关注意事项
-->
- [资源消耗]
- [执行时间]
- [并发限制]

### 环境要求
<!--
描述环境依赖要求
-->
- [系统依赖]
- [软件版本]
- [配置要求]

### 限制和约束
<!--
描述技能的限制和约束条件
-->
- [输入限制]
- [输出限制]
- [使用约束]

## 测试用例

### 测试1：正常流程测试
- **测试目的**：验证技能在正常输入下的行为
- **输入数据**：标准的有效输入
- **预期输出**：成功状态和正确结果
- **验证点**：
  - 结果准确性
  - 执行时间在预期范围内
  - 输出格式符合规范

### 测试2：边界条件测试
- **测试目的**：验证技能在边界条件下的行为
- **输入数据**：边界值或极端条件
- **预期输出**：适当的处理结果
- **验证点**：
  - 健壮性
  - 错误处理
  - 资源管理

### 测试3：错误处理测试
- **测试目的**：验证技能的错误处理能力
- **输入数据**：无效或损坏的输入
- **预期输出**：清晰的错误信息和恢复建议
- **验证点**：
  - 错误消息质量
  - 恢复能力
  - 用户体验

### 测试4：性能测试
- **测试目的**：验证技能的性能表现
- **输入数据**：大规模或复杂数据
- **预期输出**：在可接受时间内完成
- **验证点**：
  - 执行时间
  - 内存使用
  - CPU使用率

## 相关技能

<!--
列出与此技能相关的其他技能
-->

### 前置技能
- [技能名称]：描述关系
- [技能名称]：描述关系

### 后置技能
- [技能名称]：描述关系
- [技能名称]：描述关系

### 替代技能
- [技能名称]：描述关系

### 补充技能
- [技能名称]：描述关系

## 更新日志

### 版本 1.0.0 (2026-02-03)
- 初始版本发布
- 实现核心功能
- 添加基础测试用例

### 版本 [下一个版本] (计划中)
- [计划添加的功能改进]
- [性能优化]
- [扩展支持]

---

*使用提示：*
1. *复制此模板到技能目录下的 `SKILL.md` 文件*
2. *将方括号 `[]` 中的占位符替换为实际内容*
3. *删除所有注释和提示文本*
4. *确保所有示例都是真实可运行的*
5. *遵循项目规范中的格式要求*

*模板版本：1.0.0*
*最后更新：2026-02-03*
