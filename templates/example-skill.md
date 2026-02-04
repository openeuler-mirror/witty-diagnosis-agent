---
name: system-health-check
description: 检查系统健康状态，包括CPU、内存、磁盘和网络的基本指标
version: 1.0.0
category: core
author: witty-diagnosis-team
created: 2026-02-03
updated: 2026-02-03
tags:
  - health-check
  - system-monitoring
  - metrics
  - euler-os
---

# 系统健康检查

## 概述

系统健康检查技能用于快速评估欧拉OS系统的整体健康状态。它收集关键系统指标（CPU、内存、磁盘、网络），进行分析评估，并生成健康状态报告。此技能通常作为诊断流程的初始步骤，为后续详细分析提供基础数据。

## 使用时机

### 应该使用此技能的情况：
- 需要快速了解系统整体状态时
- 作为定期巡检的一部分
- 在部署新服务或应用之前
- 系统出现性能问题时进行初步检查
- 与其他诊断技能配合使用，提供基础数据

### 不应该使用此技能的情况：
- 需要深度性能分析时（使用metric-analyzer技能）
- 需要详细日志分析时（使用log-analyzer技能）
- 需要分布式追踪分析时（使用trace-analyzer技能）

## 输入要求

### 必需输入

| 参数名 | 类型 | 描述 | 示例值 |
|--------|------|------|--------|
| `session_id` | string | 诊断会话ID | `"health-check-001"` |
| `target` | string | 检查目标，必须是`"system"` | `"system"` |

### 可选输入

| 参数名 | 类型 | 默认值 | 描述 |
|--------|------|--------|------|
| `timeout` | number | `60` | 执行超时时间（秒） |
| `verbosity` | string | `"info"` | 日志详细程度：`"debug"`, `"info"`, `"warn"`, `"error"` |
| `check_items` | array | `["cpu", "memory", "disk", "network"]` | 要检查的项目列表 |
| `thresholds` | object | `{"cpu": 80, "memory": 85, "disk": 90}` | 各指标的警告阈值（百分比） |

### 输入格式示例

```json
{
  "session_id": "health-check-session-001",
  "target": "system",
  "parameters": {
    "timeout": 60,
    "verbosity": "info",
    "check_items": ["cpu", "memory", "disk", "network"],
    "thresholds": {
      "cpu": 80,
      "memory": 85,
      "disk": 90,
      "network_latency": 100
    }
  },
  "metadata": {
    "request_id": "req-health-001",
    "timestamp": "2026-02-03T17:30:00Z",
    "environment": "production"
  }
}
```

## 执行步骤

### 1. 初始化阶段
- 验证输入参数的有效性
- 初始化日志记录器，设置详细级别
- 准备临时工作目录
- 检查系统命令可用性（top, free, df, ping等）

### 2. 数据收集阶段
按顺序收集各项指标数据：
- **CPU使用率**：使用`top`命令收集1分钟、5分钟、15分钟负载和CPU使用率
- **内存使用**：使用`free`命令收集内存总量、使用量、缓存和可用内存
- **磁盘空间**：使用`df`命令收集各挂载点的使用情况
- **网络状态**：使用`ping`测试网络连通性和延迟
- **系统信息**：收集系统版本、内核版本、运行时间等信息

### 3. 分析评估阶段
对收集的数据进行分析：
- 比较各项指标与阈值
- 计算健康评分（0-100分）
- 识别潜在问题
- 生成严重性评估

### 4. 结果生成阶段
- 格式化分析结果
- 生成人类可读的报告摘要
- 收集执行统计信息
- 清理临时文件和资源

## 输出格式

### 成功输出格式

```json
{
  "status": "success",
  "session_id": "health-check-session-001",
  "execution_time": 5.2,
  "results": {
    "health_score": 85,
    "overall_status": "healthy",
    "components": {
      "cpu": {
        "status": "healthy",
        "usage_percent": 45.2,
        "load_1min": 1.2,
        "load_5min": 1.5,
        "load_15min": 1.3,
        "threshold": 80,
        "message": "CPU使用率正常"
      },
      "memory": {
        "status": "warning",
        "total_gb": 16,
        "used_gb": 13.5,
        "free_gb": 2.5,
        "usage_percent": 84.4,
        "threshold": 85,
        "message": "内存使用率接近阈值"
      },
      "disk": {
        "status": "healthy",
        "partitions": [
          {
            "mount_point": "/",
            "total_gb": 50,
            "used_gb": 25,
            "free_gb": 25,
            "usage_percent": 50,
            "threshold": 90,
            "status": "healthy"
          }
        ]
      },
      "network": {
        "status": "healthy",
        "connectivity": true,
        "avg_latency_ms": 12.5,
        "packet_loss_percent": 0,
        "threshold_latency": 100,
        "message": "网络连接正常"
      }
    },
    "issues_found": 1,
    "recommendations": [
      {
        "component": "memory",
        "severity": "warning",
        "action": "监控内存使用趋势，考虑优化应用内存使用",
        "priority": "medium"
      }
    ]
  },
  "metadata": {
    "skill_name": "system-health-check",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z",
    "system_info": {
      "os_name": "EulerOS",
      "os_version": "2.0",
      "kernel_version": "4.19.90",
      "uptime_days": 45
    }
  }
}
```

### 错误输出格式

```json
{
  "status": "error",
  "session_id": "health-check-session-001",
  "error_code": "COMMAND_EXECUTION_FAILED",
  "error_message": "执行系统命令失败，无法收集CPU指标",
  "details": {
    "failed_step": "数据收集阶段",
    "failed_command": "top -bn1",
    "exit_code": 127,
    "stderr": "command not found: top",
    "error_context": {
      "check_item": "cpu",
      "attempt_time": "2026-02-03T17:30:05Z"
    }
  },
  "suggestions": [
    "检查系统命令是否安装：top, free, df, ping",
    "确保执行用户有足够的权限",
    "尝试使用备用命令收集数据"
  ],
  "metadata": {
    "skill_name": "system-health-check",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

### 输出字段说明

| 字段名 | 类型 | 必需 | 描述 |
|--------|------|------|------|
| `status` | string | 是 | 执行状态：`"success"`, `"error"` |
| `session_id` | string | 是 | 诊断会话ID |
| `execution_time` | number | 是 | 执行时间（秒） |
| `results.health_score` | number | 是 | 健康评分（0-100） |
| `results.overall_status` | string | 是 | 整体状态：`"healthy"`, `"warning"`, `"critical"` |
| `results.components` | object | 是 | 各组件检查结果 |
| `results.issues_found` | number | 是 | 发现的问题数量 |
| `results.recommendations` | array | 是 | 修复建议列表 |
| `metadata` | object | 是 | 元数据信息 |

## 示例

### 示例1：基础健康检查

**场景描述**：
对生产环境服务器进行快速健康检查，使用默认阈值。

**命令调用**：
```bash
claude witty-diagnosis:system-health-check --target system
```

**输入数据**：
```json
{
  "session_id": "prod-health-check-001",
  "target": "system",
  "parameters": {
    "timeout": 60,
    "verbosity": "info"
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "prod-health-check-001",
  "execution_time": 4.8,
  "results": {
    "health_score": 92,
    "overall_status": "healthy",
    "components": {
      "cpu": {"status": "healthy", "usage_percent": 35.2},
      "memory": {"status": "healthy", "usage_percent": 65.8},
      "disk": {"status": "healthy", "partitions": [...]},
      "network": {"status": "healthy", "avg_latency_ms": 15.2}
    },
    "issues_found": 0,
    "recommendations": []
  },
  "metadata": {
    "skill_name": "system-health-check",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

### 示例2：自定义阈值检查

**场景描述**：
对关键业务服务器进行严格检查，使用更低的阈值。

**命令调用**：
```bash
claude witty-diagnosis:system-health-check --target system --thresholds '{"cpu": 70, "memory": 75, "disk": 80}'
```

**输入数据**：
```json
{
  "session_id": "critical-check-001",
  "target": "system",
  "parameters": {
    "timeout": 60,
    "verbosity": "info",
    "thresholds": {
      "cpu": 70,
      "memory": 75,
      "disk": 80,
      "network_latency": 50
    }
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "critical-check-001",
  "execution_time": 5.1,
  "results": {
    "health_score": 75,
    "overall_status": "warning",
    "components": {
      "cpu": {
        "status": "warning",
        "usage_percent": 72.5,
        "threshold": 70,
        "message": "CPU使用率超过严格阈值"
      },
      "memory": {"status": "healthy", "usage_percent": 68.2},
      "disk": {"status": "healthy", "partitions": [...]},
      "network": {"status": "healthy", "avg_latency_ms": 32.1}
    },
    "issues_found": 1,
    "recommendations": [
      {
        "component": "cpu",
        "severity": "warning",
        "action": "CPU使用率较高，建议检查运行进程或考虑扩容",
        "priority": "high"
      }
    ]
  },
  "metadata": {
    "skill_name": "system-health-check",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

## 注意事项

### 安全注意事项
- 需要读取系统信息的权限，但不需要root权限
- 不收集敏感信息（如用户数据、密码等）
- 所有收集的数据在会话结束后自动清理
- 网络检查只测试连通性，不进行端口扫描或安全测试

### 性能注意事项
- 执行时间通常在5-10秒内
- 网络检查会增加额外时间（取决于ping目标）
- 可以调整`timeout`参数控制最长执行时间
- 建议不要过于频繁执行（间隔至少1分钟）

### 环境要求
- 欧拉OS 2.0或更高版本
- 需要以下系统命令：`top`, `free`, `df`, `ping`
- 需要基本的shell执行权限
- 网络检查需要外部网络可达

### 限制和约束
- 只能检查本地系统，不能检查远程系统
- 网络检查依赖外部可达的测试目标（默认8.8.8.8）
- 磁盘检查只检查已挂载的文件系统
- 内存检查不包括swap使用情况

## 测试用例

### 测试1：正常流程测试
- **测试目的**：验证技能在正常系统上的完整流程
- **输入数据**：标准健康检查请求
- **预期输出**：成功状态，包含所有组件的检查结果
- **验证点**：所有检查项目都执行，结果格式正确，执行时间<10秒

### 测试2：高负载系统测试
- **测试目的**：验证技能在高负载系统上的行为
- **输入数据**：模拟CPU使用率90%，内存使用率95%
- **预期输出**：警告状态，正确的严重性评估
- **验证点**：正确识别问题，提供适当的建议

### 测试3：命令缺失测试
- **测试目的**：验证技能在缺少系统命令时的错误处理
- **输入数据**：正常请求，但移除`top`命令
- **预期输出**：错误状态，清晰的错误信息和建议
- **验证点**：错误信息有帮助性，建议可操作

### 测试4：超时测试
- **测试目的**：验证技能的超时处理
- **输入数据**：设置超时时间为1秒
- **预期输出**：超时错误，部分结果可能可用
- **验证点**：在超时前优雅停止，清理资源

## 相关技能

### 前置技能
- 无（此技能通常是诊断流程的起点）

### 后置技能
- **metric-analyzer**：进行更详细的指标分析和趋势预测
- **log-analyzer**：如果发现异常，进行日志分析
- **fault-localization**：如果发现严重问题，进行故障定位

### 替代技能
- 无直接替代技能，但可以与其他监控工具配合使用

### 补充技能
- **intelligent-inspection**：定期自动执行健康检查
- **knowledge-base**：记录历史健康状态，建立基线

## 更新日志

### 版本 1.0.0 (2026-02-03)
- 初始版本发布
- 实现CPU、内存、磁盘、网络基础检查
- 添加健康评分计算
- 支持自定义阈值
- 包含完整的错误处理

### 版本 1.1.0 (计划中)
- 添加进程级检查
- 支持检查特定服务状态
- 添加性能基线比较
- 支持导出检查报告为HTML格式

---

*这是一个完整的技能示例，展示了如何编写符合规范的技能文档。*
*实际技能开发时应参考此示例的结构和详细程度。*
