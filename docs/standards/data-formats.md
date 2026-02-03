# 数据格式规范

## 概述

本规范定义了witty-diagnosis-agent项目中所有数据交换的格式标准。统一的格式规范确保技能间的兼容性、数据的一致性和系统的可维护性。

## 1. 通用格式原则

### 1.1 编码和字符集
- 所有文本数据使用UTF-8编码
- JSON文件使用无BOM的UTF-8编码
- 行尾使用LF（Unix风格）

### 1.2 日期和时间格式
- 使用ISO 8601扩展格式：`YYYY-MM-DDTHH:mm:ss.sssZ`
- 时区：UTC（使用Z后缀）
- 示例：`2026-02-03T17:30:00.123Z`

### 1.3 数字格式
- 整数：无前导零，除非表示八进制
- 浮点数：使用小数点，科学计数法可选
- 大数字：可使用下划线提高可读性（JSON中不允许）

### 1.4 布尔值
- 使用`true`和`false`（小写）
- 避免使用`1`/`0`或`"true"`/`"false"`

## 2. 输入数据格式

### 2.1 通用输入格式

所有技能输入必须遵循以下基本结构：

```json
{
  "session_id": "string",
  "target": "string",
  "parameters": {
    // 技能特定参数
  },
  "metadata": {
    // 元数据信息
  }
}
```

### 2.2 字段定义

#### 必需字段
| 字段名 | 类型 | 必需 | 描述 | 示例 |
|--------|------|------|------|------|
| `session_id` | string | 是 | 诊断会话的唯一标识符 | `"diagnosis-20260203-001"` |
| `target` | string | 是 | 诊断目标类型 | `"system"`, `"network"`, `"storage"`, `"security"` |

#### 可选字段
| 字段名 | 类型 | 必需 | 描述 | 示例 |
|--------|------|------|------|------|
| `parameters` | object | 否 | 技能特定的参数 | `{"timeout": 300}` |
| `metadata` | object | 否 | 元数据信息 | `{"request_id": "req-001"}` |

### 2.3 参数规范

#### 通用参数
所有技能都应支持以下通用参数：

```json
{
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    "output_format": "json",
    "dry_run": false
  }
}
```

| 参数名 | 类型 | 默认值 | 有效值 | 描述 |
|--------|------|--------|--------|------|
| `timeout` | integer | `300` | `1-3600` | 执行超时时间（秒） |
| `verbosity` | string | `"info"` | `"debug"`, `"info"`, `"warn"`, `"error"` | 日志详细程度 |
| `output_format` | string | `"json"` | `"json"`, `"yaml"`, `"text"` | 输出格式 |
| `dry_run` | boolean | `false` | `true`, `false` | 模拟执行，不实际修改系统 |

### 2.4 元数据规范

```json
{
  "metadata": {
    "request_id": "string",
    "timestamp": "ISO8601",
    "source": "string",
    "environment": "string",
    "user": {
      "id": "string",
      "name": "string",
      "role": "string"
    },
    "context": {
      // 上下文信息
    }
  }
}
```

## 3. 输出数据格式

### 3.1 通用输出格式

所有技能输出必须遵循以下基本结构：

```json
{
  "status": "string",
  "session_id": "string",
  "execution_time": number,
  "results": {
    // 技能特定的结果数据
  },
  "metadata": {
    // 元数据信息
  }
}
```

### 3.2 状态定义

#### 成功状态
```json
{
  "status": "success",
  "session_id": "diagnosis-001",
  "execution_time": 45.2,
  "results": {
    // 成功结果
  },
  "metadata": {
    "skill_name": "skill-name",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

#### 部分成功状态
```json
{
  "status": "partial",
  "session_id": "diagnosis-001",
  "execution_time": 45.2,
  "results": {
    // 部分结果
  },
  "partial_results": {
    "successful_items": ["item1", "item2"],
    "failed_items": ["item3"],
    "failure_reasons": {
      "item3": "资源不足"
    }
  },
  "metadata": {
    "skill_name": "skill-name",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

#### 错误状态
```json
{
  "status": "error",
  "session_id": "diagnosis-001",
  "execution_time": 5.1,
  "error_code": "ERROR_CODE",
  "error_message": "人类可读的错误描述",
  "details": {
    "failed_step": "步骤名称",
    "error_context": {
      // 错误上下文
    }
  },
  "suggestions": [
    "修复建议1",
    "修复建议2"
  ],
  "metadata": {
    "skill_name": "skill-name",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

### 3.3 错误代码规范

#### 错误代码格式
- 格式：`CATEGORY_SUBCATEGORY_DETAIL`
- 示例：`VALIDATION_INPUT_INVALID`, `EXECUTION_TIMEOUT_EXCEEDED`

#### 标准错误代码
| 错误代码 | 描述 | HTTP等效 | 严重程度 |
|----------|------|-----------|----------|
| `VALIDATION_INPUT_INVALID` | 输入验证失败 | 400 | 错误 |
| `VALIDATION_PARAMETER_MISSING` | 必需参数缺失 | 400 | 错误 |
| `VALIDATION_PARAMETER_INVALID` | 参数值无效 | 400 | 错误 |
| `EXECUTION_TIMEOUT_EXCEEDED` | 执行超时 | 408 | 错误 |
| `EXECUTION_RESOURCE_UNAVAILABLE` | 资源不可用 | 503 | 错误 |
| `EXECUTION_PERMISSION_DENIED` | 权限不足 | 403 | 错误 |
| `EXECUTION_EXTERNAL_FAILURE` | 外部依赖失败 | 502 | 错误 |
| `DATA_FORMAT_INVALID` | 数据格式无效 | 400 | 错误 |
| `DATA_SOURCE_UNAVAILABLE` | 数据源不可用 | 503 | 错误 |

### 3.4 结果数据规范

#### 通用结果结构
```json
{
  "results": {
    "summary": {
      "total_items": 10,
      "successful_items": 8,
      "failed_items": 2,
      "execution_status": "completed"
    },
    "data": {
      // 具体数据
    },
    "metrics": {
      // 性能指标
    },
    "issues": [
      // 发现的问题
    ],
    "recommendations": [
      // 建议
    ]
  }
}
```

## 4. 诊断数据格式

### 4.1 系统指标数据

```json
{
  "type": "system_metrics",
  "timestamp": "2026-02-03T17:30:00Z",
  "hostname": "server-01",
  "metrics": {
    "cpu": {
      "usage_percent": 45.2,
      "load_1min": 1.2,
      "load_5min": 1.5,
      "load_15min": 1.3,
      "cores": 8,
      "frequency_mhz": 2400
    },
    "memory": {
      "total_bytes": 17179869184,
      "used_bytes": 11596411699,
      "free_bytes": 5583457485,
      "available_bytes": 6442450944,
      "usage_percent": 67.5,
      "swap_total_bytes": 8589934592,
      "swap_used_bytes": 1073741824
    },
    "disk": [
      {
        "device": "/dev/sda1",
        "mount_point": "/",
        "total_bytes": 53687091200,
        "used_bytes": 26843545600,
        "free_bytes": 26843545600,
        "usage_percent": 50.0,
        "inodes_total": 1310720,
        "inodes_used": 524288
      }
    ],
    "network": {
      "interfaces": [
        {
          "name": "eth0",
          "ip_address": "192.168.1.100",
          "rx_bytes": 1024000,
          "tx_bytes": 512000,
          "rx_packets": 1000,
          "tx_packets": 500
        }
      ]
    }
  }
}
```

### 4.2 日志数据格式

```json
{
  "type": "log_entry",
  "timestamp": "2026-02-03T17:30:00Z",
  "hostname": "server-01",
  "source": "/var/log/messages",
  "level": "ERROR",
  "message": "Disk write error on /dev/sda1",
  "component": "kernel",
  "process_id": 1234,
  "thread_id": 5678,
  "context": {
    "device": "/dev/sda1",
    "error_code": "EIO",
    "sector": 123456
  },
  "raw_line": "Feb  3 17:30:00 server-01 kernel: [123456.789] Disk write error on /dev/sda1, sector 123456, error -5"
}
```

### 4.3 问题报告格式

```json
{
  "type": "issue_report",
  "id": "issue-20260203-001",
  "timestamp": "2026-02-03T17:30:00Z",
  "severity": "CRITICAL",
  "component": "storage",
  "title": "磁盘空间严重不足",
  "description": "根分区使用率超过95%，可能影响系统运行",
  "details": {
    "mount_point": "/",
    "usage_percent": 95.8,
    "free_bytes": 2147483648,
    "threshold": 90
  },
  "impact": {
    "affected_services": ["web-server", "database"],
    "risk_level": "high",
    "estimated_recovery_time": "30分钟"
  },
  "evidence": [
    {
      "type": "metric",
      "source": "system_metrics",
      "timestamp": "2026-02-03T17:30:00Z",
      "data": {
        "usage_percent": 95.8
      }
    }
  ],
  "recommendations": [
    {
      "priority": "immediate",
      "action": "清理临时文件",
      "command": "rm -rf /tmp/*",
      "estimated_time": "5分钟",
      "risk": "low"
    },
    {
      "priority": "short_term",
      "action": "扩展磁盘空间",
      "description": "增加磁盘容量或迁移数据",
      "estimated_time": "2小时",
      "risk": "medium"
    }
  ]
}
```

### 4.4 修复操作格式

```json
{
  "type": "repair_operation",
  "id": "repair-20260203-001",
  "timestamp": "2026-02-03T17:30:00Z",
  "issue_id": "issue-20260203-001",
  "action": "clean_temp_files",
  "description": "清理临时文件释放磁盘空间",
  "parameters": {
    "target_path": "/tmp",
    "max_age_days": 7,
    "dry_run": false
  },
  "steps": [
    {
      "step": 1,
      "action": "check_disk_space",
      "command": "df -h /",
      "expected_output": "包含磁盘使用信息"
    },
    {
      "step": 2,
      "action": "list_old_files",
      "command": "find /tmp -type f -mtime +7",
      "expected_output": "列出超过7天的文件"
    },
    {
      "step": 3,
      "action": "remove_files",
      "command": "find /tmp -type f -mtime +7 -delete",
      "expected_output": "无输出（成功执行）"
    }
  ],
  "verification": {
    "method": "check_disk_usage",
    "command": "df -h / | awk 'NR==2 {print $5}'",
    "expected_result": "使用率小于90%",
    "timeout": 60
  },
  "rollback": {
    "available": false,
    "reason": "文件删除操作不可逆"
  },
  "permissions": {
    "required": "root",
    "reason": "需要删除系统临时文件的权限"
  }
}
```

## 5. 配置数据格式

### 5.1 技能配置格式

```yaml
# config/skills/skill-name.yaml
skill:
  name: skill-name
  version: 1.0.0
  enabled: true
  category: core

  # 执行配置
  execution:
    timeout: 300
    max_retries: 3
    retry_delay: 10

  # 资源限制
  resources:
    max_memory_mb: 512
    max_cpu_percent: 50

  # 输入验证
  validation:
    required_parameters:
      - session_id
      - target
    parameter_constraints:
      timeout:
        min: 1
        max: 3600
        default: 300

  # 输出配置
  output:
    default_format: json
    supported_formats:
      - json
      - yaml
      - text

  # 依赖配置
  dependencies:
    skills:
      - data-collector
    commands:
      - top
      - free
      - df

  # 监控配置
  monitoring:
    metrics_enabled: true
    log_level: info
    performance_threshold_ms: 1000
```

### 5.2 全局配置格式

```yaml
# config/global.yaml
global:
  project:
    name: witty-diagnosis-agent
    version: 1.0.0
    environment: production

  # 日志配置
  logging:
    level: info
    format: json
    output:
      file: /var/log/witty-diagnosis/agent.log
      max_size_mb: 100
      max_files: 10

  # 性能配置
  performance:
    max_concurrent_sessions: 10
    session_timeout_seconds: 3600
    cache_enabled: true
    cache_ttl_seconds: 300

  # 安全配置
  security:
    encryption_enabled: true
    audit_logging: true
    permission_check: true

  # 网络配置
  network:
    proxy: null
    timeout_seconds: 30
    retry_attempts: 3

  # 存储配置
  storage:
    data_directory: /var/lib/witty-diagnosis
    max_disk_usage_percent: 80
    cleanup_interval_hours: 24
```

## 6. 验证规则

### 6.1 JSON Schema验证

每个数据格式应有对应的JSON Schema进行验证：

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://witty-diagnosis-agent/schemas/input-v1.0.0.json",
  "title": "技能输入格式",
  "description": "技能输入数据的标准格式",
  "type": "object",
  "required": ["session_id", "target"],
  "properties": {
    "session_id": {
      "type": "string",
      "pattern": "^[a-zA-Z0-9_-]+$",
      "minLength": 1,
      "maxLength": 100
    },
    "target": {
      "type": "string",
      "enum": ["system", "network", "storage", "security"]
    }
  }
}
```

### 6.2 自定义验证规则

除了JSON Schema，还应实现以下自定义验证：

1. **业务逻辑验证**：参数值的业务合理性
2. **依赖验证**：检查所需资源是否可用
3. **权限验证**：检查执行权限
4. **环境验证**：检查运行环境是否符合要求

## 7. 版本管理

### 7.1 格式版本控制

- 使用语义化版本控制：`MAJOR.MINOR.PATCH`
- 主版本变更：不兼容的格式修改
- 次版本变更：向后兼容的功能增加
- 修订号变更：向后兼容的问题修复

### 7.2 向后兼容性

- 新版本必须能够读取旧版本数据
- 废弃字段应标记为`deprecated`并保持支持至少两个主版本
- 提供数据迁移工具和指南

## 8. 性能考虑

### 8.1 数据大小限制

| 数据类型 | 建议大小限制 | 压缩要求 |
|----------|--------------|----------|
| 输入数据 | < 1MB | 可选 |
| 输出数据 | < 10MB | 建议 |
| 日志数据 | < 100KB/条 | 不适用 |
| 配置文件 | < 100KB | 不适用 |

### 8.2 序列化性能

- 优先使用JSON而非XML
- 对于大量数据，考虑使用MessagePack或Protocol Buffers
- 避免深度嵌套的结构
- 使用数组而非对象存储同类数据

## 9. 安全考虑

### 9.1 数据脱敏

敏感信息应在输出前脱敏：

```json
{
  "password": "********",
  "api_key": "sk_****1234",
  "credit_card": "****-****-****-1234"
}
```

### 9.2 输入验证

- 所有输入必须验证
- 防止注入攻击
- 限制数据大小和类型
- 使用白名单验证枚举值

---

*文档版本：1.0.0*
*创建日期：2026-02-03*
*更新日期：2026-02-03*
