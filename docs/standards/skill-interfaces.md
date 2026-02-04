# 技能接口规范

## 概述

本规范定义了witty-diagnosis-agent项目中技能间的通信接口标准。统一的接口规范确保技能能够正确交互、数据能够顺畅流动，并支持技能的组合和重用。

## 1. 接口设计原则

### 1.1 设计原则
- **单一职责**：每个接口专注于一个明确的功能
- **明确契约**：输入输出格式明确，行为可预测
- **向后兼容**：接口变更保持向后兼容性
- **错误友好**：提供清晰的错误信息和恢复建议
- **可观测性**：支持监控、日志和追踪

### 1.2 接口类型
| 接口类型 | 用途 | 通信方式 | 示例 |
|----------|------|----------|------|
| **同步调用** | 实时请求-响应 | 函数调用/HTTP | 数据收集、分析计算 |
| **异步消息** | 长时间任务 | 消息队列/事件 | 批量处理、定期任务 |
| **数据流** | 连续数据处理 | 流式API/管道 | 实时监控、日志分析 |
| **事件驱动** | 状态变化通知 | 事件总线 | 故障告警、状态更新 |

## 2. 同步调用接口

### 2.1 基本调用模式

```json
// 请求格式
{
  "interface": "sync",
  "operation": "execute",
  "request_id": "req-001",
  "timestamp": "2026-02-03T17:30:00Z",
  "data": {
    // 具体请求数据
  }
}

// 响应格式
{
  "interface": "sync",
  "operation": "execute",
  "request_id": "req-001",
  "timestamp": "2026-02-03T17:30:00Z",
  "status": "success",
  "data": {
    // 响应数据
  }
}
```

### 2.2 标准操作

#### 执行操作 (execute)
```json
{
  "interface": "sync",
  "operation": "execute",
  "request_id": "req-execute-001",
  "skill": "data-collector",
  "data": {
    "session_id": "session-001",
    "target": "system",
    "parameters": {
      "timeout": 300
    }
  }
}
```

#### 验证操作 (validate)
```json
{
  "interface": "sync",
  "operation": "validate",
  "request_id": "req-validate-001",
  "skill": "data-collector",
  "data": {
    "session_id": "session-001",
    "target": "system"
  }
}
```

#### 状态检查 (status)
```json
{
  "interface": "sync",
  "operation": "status",
  "request_id": "req-status-001",
  "skill": "data-collector"
}
```

### 2.3 超时和重试

```yaml
# 超时配置
timeout:
  default: 300  # 默认超时（秒）
  per_operation:
    execute: 300
    validate: 30
    status: 10

# 重试配置
retry:
  max_attempts: 3
  backoff:
    initial: 1  # 初始延迟（秒）
    multiplier: 2
    max: 10  # 最大延迟（秒）
  retryable_errors:
    - "TIMEOUT"
    - "NETWORK_ERROR"
    - "RESOURCE_BUSY"
```

## 3. 技能间数据传递

### 3.1 数据传递模式

#### 管道模式 (Pipe)
```bash
# 命令行管道
claude witty-diagnosis:data-collector | \
claude witty-diagnosis:log-analyzer | \
claude witty-diagnosis:fault-localization
```

#### 链式调用 (Chain)
```json
{
  "chain": [
    {
      "skill": "data-collector",
      "input": {
        "target": "system"
      }
    },
    {
      "skill": "log-analyzer",
      "input": {
        "use_previous_output": true
      }
    },
    {
      "skill": "fault-localization",
      "input": {
        "use_previous_output": true
      }
    }
  ]
}
```

#### 并行执行 (Parallel)
```json
{
  "parallel": [
    {
      "skill": "data-collector",
      "input": {
        "target": "system"
      }
    },
    {
      "skill": "metric-analyzer",
      "input": {
        "target": "system"
      }
    }
  ],
  "aggregator": "result-aggregator"
}
```

### 3.2 数据上下文传递

```json
{
  "session_id": "session-001",
  "context": {
    "previous_results": {
      "data-collector": {
        "status": "success",
        "execution_time": 45.2,
        "results": {
          // 数据收集结果
        }
      }
    },
    "shared_data": {
      "system_info": {
        "hostname": "server-01",
        "os_version": "EulerOS 2.0"
      },
      "environment": "production"
    },
    "chain_position": 2,
    "total_chains": 3
  },
  "current_input": {
    // 当前技能输入
  }
}
```

## 4. 事件接口

### 4.1 事件格式

```json
{
  "event_id": "event-20260203-001",
  "event_type": "DIAGNOSIS_STARTED",
  "timestamp": "2026-02-03T17:30:00Z",
  "source": "diagnosis-agent",
  "severity": "INFO",
  "data": {
    "session_id": "session-001",
    "target": "system",
    "initiator": "user@example.com"
  },
  "correlation_id": "corr-001",
  "metadata": {
    "version": "1.0.0",
    "environment": "production"
  }
}
```

### 4.2 标准事件类型

#### 诊断事件
| 事件类型 | 触发时机 | 数据内容 |
|----------|----------|----------|
| `DIAGNOSIS_STARTED` | 诊断开始时 | 会话信息、目标 |
| `DIAGNOSIS_COMPLETED` | 诊断完成时 | 结果摘要、执行时间 |
| `DIAGNOSIS_FAILED` | 诊断失败时 | 错误信息、失败原因 |
| `SKILL_EXECUTION_STARTED` | 技能开始时 | 技能名称、输入 |
| `SKILL_EXECUTION_COMPLETED` | 技能完成时 | 技能结果、执行时间 |
| `ISSUE_DETECTED` | 发现问题时 | 问题详情、严重程度 |

#### 系统事件
| 事件类型 | 触发时机 | 数据内容 |
|----------|----------|----------|
| `SYSTEM_HEALTH_CHANGED` | 系统健康变化 | 健康状态、变化详情 |
| `RESOURCE_THRESHOLD_EXCEEDED` | 资源超阈值 | 资源类型、当前值、阈值 |
| `CONFIGURATION_CHANGED` | 配置变更时 | 变更内容、变更者 |

### 4.3 事件订阅和发布

```yaml
# 事件订阅配置
event_subscriptions:
  - event_type: "ISSUE_DETECTED"
    severity: ["WARNING", "ERROR", "CRITICAL"]
    skills:
      - knowledge-base
      - notification-agent
    actions:
      - "record_issue"
      - "send_alert"

  - event_type: "DIAGNOSIS_COMPLETED"
    severity: ["INFO"]
    skills:
      - report-generator
    actions:
      - "generate_report"
```

## 5. 错误处理和恢复

### 5.1 错误传播

```json
{
  "skill": "fault-localization",
  "status": "error",
  "error": {
    "code": "DEPENDENCY_FAILED",
    "message": "依赖技能执行失败",
    "details": {
      "failed_skill": "data-collector",
      "skill_error": {
        "code": "EXECUTION_TIMEOUT_EXCEEDED",
        "message": "数据收集超时"
      }
    }
  },
  "recovery_options": [
    {
      "action": "retry_with_timeout",
      "parameters": {
        "timeout": 600
      },
      "description": "使用更长超时时间重试数据收集"
    },
    {
      "action": "use_cached_data",
      "parameters": {
        "max_age_minutes": 60
      },
      "description": "使用最近一小时的缓存数据"
    },
    {
      "action": "skip_and_continue",
      "parameters": {
        "skip_skill": "data-collector"
      },
      "description": "跳过数据收集，使用默认值继续"
    }
  ]
}
```

### 5.2 重试策略

```yaml
retry_strategies:
  exponential_backoff:
    max_attempts: 3
    initial_delay_ms: 1000
    multiplier: 2
    max_delay_ms: 10000

  fixed_interval:
    max_attempts: 5
    interval_ms: 2000

  circuit_breaker:
    failure_threshold: 5
    reset_timeout_ms: 60000
    half_open_max_calls: 3
```

### 5.3 降级策略

```json
{
  "primary_skill": "metric-analyzer",
  "fallback_skills": [
    {
      "skill": "simple-metric-check",
      "conditions": [
        "primary_skill_unavailable",
        "time_constrained"
      ],
      "capabilities": ["basic_metrics"]
    },
    {
      "skill": "cached-metric-analysis",
      "conditions": ["network_unavailable"],
      "capabilities": ["historical_analysis"]
    }
  ],
  "degradation_levels": [
    {
      "level": "full",
      "description": "完整功能",
      "required_skills": ["metric-analyzer"]
    },
    {
      "level": "basic",
      "description": "基础功能",
      "required_skills": ["simple-metric-check"]
    },
    {
      "level": "offline",
      "description": "离线模式",
      "required_skills": ["cached-metric-analysis"]
    }
  ]
}
```

## 6. 性能接口

### 6.1 性能指标收集

```json
{
  "skill": "data-collector",
  "session_id": "session-001",
  "performance_metrics": {
    "execution_time_ms": 4520,
    "cpu_usage_percent": 15.2,
    "memory_usage_mb": 128.5,
    "network_io_bytes": 1048576,
    "disk_io_bytes": 524288,
    "concurrent_executions": 3,
    "cache_hit_rate": 0.85
  },
  "timings": {
    "initialization_ms": 120,
    "data_collection_ms": 4200,
    "processing_ms": 150,
    "cleanup_ms": 50
  },
  "resource_usage": {
    "peak_memory_mb": 156.2,
    "peak_cpu_percent": 25.8,
    "open_files": 12,
    "threads": 4
  }
}
```

### 6.2 性能监控接口

```yaml
performance_monitoring:
  enabled: true
  collection_interval_seconds: 60
  metrics:
    - name: "execution_time"
      type: "histogram"
      buckets: [100, 500, 1000, 5000, 10000]
      labels: ["skill", "target"]

    - name: "success_rate"
      type: "gauge"
      labels: ["skill", "target"]

    - name: "resource_usage"
      type: "summary"
      labels: ["skill", "resource_type"]

  alerts:
    - metric: "execution_time"
      condition: "> 10000"
      severity: "warning"
      message: "技能执行时间过长"

    - metric: "success_rate"
      condition: "< 0.95"
      severity: "error"
      message: "技能成功率下降"
```

## 7. 配置接口

### 7.1 配置查询和更新

```json
// 查询配置
{
  "interface": "config",
  "operation": "get",
  "request_id": "req-config-get-001",
  "skill": "data-collector",
  "keys": ["execution.timeout", "output.format"]
}

// 响应
{
  "interface": "config",
  "operation": "get",
  "request_id": "req-config-get-001",
  "skill": "data-collector",
  "config": {
    "execution": {
      "timeout": 300
    },
    "output": {
      "format": "json"
    }
  }
}

// 更新配置
{
  "interface": "config",
  "operation": "update",
  "request_id": "req-config-update-001",
  "skill": "data-collector",
  "changes": {
    "execution.timeout": 600,
    "output.format": "yaml"
  },
  "validation": true
}
```

### 7.2 配置验证接口

```json
{
  "interface": "config",
  "operation": "validate",
  "request_id": "req-config-validate-001",
  "skill": "data-collector",
  "config": {
    "execution": {
      "timeout": 50  # 无效值，应大于60
    }
  }
}

// 响应
{
  "interface": "config",
  "operation": "validate",
  "request_id": "req-config-validate-001",
  "skill": "data-collector",
  "valid": false,
  "errors": [
    {
      "path": "execution.timeout",
      "error": "值必须大于等于60",
      "current_value": 50,
      "allowed_range": "60-3600"
    }
  ],
  "suggestions": [
    "将timeout设置为至少60秒"
  ]
}
```

## 8. 扩展接口

### 8.1 插件接口

```json
{
  "interface": "plugin",
  "operation": "register",
  "request_id": "req-plugin-register-001",
  "plugin": {
    "name": "custom-metric-collector",
    "version": "1.0.0",
    "type": "metric-provider",
    "capabilities": ["custom_metrics", "real_time"],
    "endpoints": {
      "collect": "/metrics/collect",
      "health": "/health"
    },
    "config_schema": {
      // JSON Schema定义
    }
  }
}
```

### 8.2 自定义处理器接口

```json
{
  "interface": "processor",
  "operation": "transform",
  "request_id": "req-processor-transform-001",
  "processor": "custom-data-formatter",
  "input": {
    "data": {
      // 原始数据
    },
    "format": "custom-format"
  },
  "parameters": {
    "include_metadata": true,
    "compress": false
  }
}
```

## 9. 接口版本管理

### 9.1 版本标识

```http
# HTTP接口版本
GET /api/v1/skills/data-collector/execute

# 消息接口版本
{
  "interface_version": "1.0.0",
  "skill_version": "1.2.0",
  "compatibility": ["1.0.x", "1.1.x"]
}
```

### 9.2 版本协商

```json
{
  "interface": "version",
  "operation": "negotiate",
  "request_id": "req-version-negotiate-001",
  "client_versions": {
    "data_format": "1.0.0",
    "skill_interface": "1.1.0",
    "event_system": "1.0.0"
  },
  "supported_versions": {
    "data_format": ["1.0.0", "1.1.0"],
    "skill_interface": ["1.0.0", "1.1.0", "1.2.0"],
    "event_system": ["1.0.0"]
  }
}

// 响应
{
  "interface": "version",
  "operation": "negotiate",
  "request_id": "req-version-negotiate-001",
  "negotiated_versions": {
    "data_format": "1.0.0",
    "skill_interface": "1.1.0",
    "event_system": "1.0.0"
  },
  "deprecation_warnings": [
    {
      "component": "skill_interface",
      "version": "1.1.0",
      "message": "将在v2.0.0中废弃",
      "alternative": "使用1.2.0版本"
    }
  ]
}
```

## 10. 测试接口

### 10.1 接口测试

```json
{
  "interface": "test",
  "operation": "integration",
  "request_id": "req-test-integration-001",
  "test_scenario": "data-flow-chain",
  "skills": ["data-collector", "log-analyzer", "fault-localization"],
  "inputs": [
    {
      "skill": "data-collector",
      "data": {
        "target": "system"
      }
    }
  ],
  "expected_outputs": [
    {
      "skill": "fault-localization",
      "validations": [
        {
          "path": "results.issues_found",
          "type": "number",
          "condition": ">= 0"
        }
      ]
    }
  ],
  "timeout": 300
}
```

### 10.2 性能测试接口

```json
{
  "interface": "test",
  "operation": "performance",
  "request_id": "req-test-performance-001",
  "skill": "data-collector",
  "test_type": "load",
  "parameters": {
    "concurrent_requests": 10,
    "duration_seconds": 300,
    "request_rate": 5
  },
  "metrics_to_collect": [
    "response_time",
    "throughput",
    "error_rate",
    "resource_usage"
  ],
  "success_criteria": {
    "avg_response_time_ms": "< 1000",
    "p95_response_time_ms": "< 2000",
    "error_rate": "< 0.01",
    "cpu_usage_percent": "< 80"
  }
}
```

---

*文档版本：1.0.0*
*创建日期：2026-02-03*
*更新日期：2026-02-03*
