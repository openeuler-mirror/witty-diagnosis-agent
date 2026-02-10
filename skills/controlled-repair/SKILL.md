---
name: controlled-repair
description: 安全可控的修复操作技能，负责在欧拉OS系统上执行安全修复操作，包括修复操作安全控制、操作回滚机制、修复效果验证、权限检查和风险评估
version: 1.0.0
category: core
author: witty-diagnosis-team
created: 2026-02-03
updated: 2026-02-03
tags:
  - repair
  - safety
  - rollback
  - risk-assessment
  - euler-os
  - diagnostics
  - security
---

# 可控修复 - 安全可控的修复操作技能

## 概述

可控修复技能是witty-diagnosis-agent项目的核心修复组件，专门设计用于在欧拉OS系统上执行安全、可控的修复操作。本技能强调"安全第一"原则，确保所有修复操作都在严格的控制下进行，支持操作回滚、效果验证和风险评估。

主要功能包括：
1. **修复操作安全控制**：确保修复操作的安全性，防止误操作
2. **操作回滚机制**：支持操作失败时的自动或手动回滚
3. **修复效果验证**：验证修复操作的实际效果
4. **权限检查**：检查执行修复操作所需的权限
5. **风险评估**：评估修复操作的风险，提供风险缓解建议

本技能通常在root-cause-analysis技能之后执行，基于诊断结果执行相应的修复操作。它是诊断修复流程的关键环节，确保修复操作的安全性和有效性。

## 使用时机

### 应该使用此技能的情况：
- 已经完成根因分析，需要执行修复操作时
- 系统出现已知问题，有明确的修复方案时
- 需要安全地重启服务或应用配置时
- 需要回滚失败的配置变更时
- 执行高风险操作前需要风险评估时
- 需要验证修复操作效果时

### 不应该使用此技能的情况：
- 问题原因尚未明确时（应先使用root-cause-analysis）
- 没有明确的修复方案时
- 修复操作风险过高且无缓解措施时
- 缺乏必要的执行权限时
- 生产环境关键系统无充分测试时

## 输入要求

### 必需输入

| 参数名 | 类型 | 描述 | 示例值 |
|--------|------|------|--------|
| `session_id` | string | 诊断会话ID | `"repair-session-001"` |
| `target` | string | 修复目标类型 | `"service"`, `"config"`, `"process"`, `"network"`, `"storage"` |
| `repair_action` | string | 修复操作类型 | `"restart"`, `"rollback"`, `"reconfigure"`, `"cleanup"`, `"recover"` |
| `repair_target` | string | 具体的修复目标 | `"nginx.service"`, `"/etc/nginx/nginx.conf"`, `"process-1234"` |

### 可选输入

| 参数名 | 类型 | 默认值 | 描述 |
|--------|------|--------|------|
| `timeout` | number | `300` | 执行超时时间（秒） |
| `verbosity` | string | `"info"` | 日志详细程度：`"debug"`, `"info"`, `"warn"`, `"error"` |
| `require_approval` | boolean | `true` | 是否需要人工审批（高风险操作） |
| `auto_rollback` | boolean | `true` | 操作失败时是否自动回滚 |
| `rollback_timeout` | number | `60` | 回滚操作超时时间（秒） |
| `verification_interval` | number | `5` | 效果验证检查间隔（秒） |
| `verification_attempts` | number | `3` | 效果验证尝试次数 |
| `risk_threshold` | string | `"medium"` | 风险阈值：`"low"`, `"medium"`, `"high"` |
| `dry_run` | boolean | `false` | 模拟执行，不实际执行操作 |
| `backup_before_repair` | boolean | `true` | 修复前是否备份 |
| `backup_location` | string | `"/var/backups"` | 备份文件存储位置 |

### 输入格式示例

```json
{
  "session_id": "controlled-repair-session-001",
  "target": "service",
  "repair_action": "restart",
  "repair_target": "nginx.service",
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    "require_approval": false,
    "auto_rollback": true,
    "rollback_timeout": 60,
    "verification_interval": 5,
    "verification_attempts": 3,
    "risk_threshold": "medium",
    "dry_run": false,
    "backup_before_repair": true,
    "backup_location": "/var/backups/witty-diagnosis"
  },
  "metadata": {
    "request_id": "req-repair-001",
    "timestamp": "2026-02-03T17:30:00Z",
    "environment": "production",
    "user": {
      "id": "admin",
      "role": "system-admin"
    },
    "diagnosis_result": {
      "root_cause": "nginx配置错误导致服务崩溃",
      "confidence": 0.95,
      "recommended_action": "重启nginx服务并验证配置"
    }
  }
}
```

## 执行步骤

### 1. 初始化阶段
- **参数验证**：验证输入参数的有效性和完整性
- **权限检查**：检查执行用户对修复目标的访问权限
- **风险评估**：评估修复操作的风险等级，与阈值比较
- **审批检查**：如果需要审批，等待人工确认
- **环境准备**：创建临时工作目录，初始化日志记录器
- **备份创建**：如果启用备份，创建修复前的备份

### 2. 安全控制阶段
- **操作锁定**：锁定修复目标，防止并发操作
- **前置检查**：执行修复前的系统状态检查
- **依赖验证**：验证修复操作的依赖条件
- **影响评估**：评估修复操作对系统的影响范围
- **应急预案**：准备操作失败的应急预案

### 3. 修复执行阶段（分步骤执行）
根据`repair_action`参数执行相应的修复操作：

#### 服务重启操作（restart）
- **服务状态检查**：检查服务的当前状态
- **优雅停止**：尝试优雅停止服务
- **强制停止**：如果优雅停止失败，强制停止服务
- **服务启动**：启动服务并检查启动状态
- **启动验证**：验证服务是否成功启动

#### 配置回滚操作（rollback）
- **备份查找**：查找最近的可用备份
- **备份验证**：验证备份的完整性和可用性
- **当前配置备份**：备份当前配置
- **配置恢复**：恢复备份配置
- **配置验证**：验证恢复的配置

#### 配置更新操作（reconfigure）
- **配置语法检查**：检查新配置的语法正确性
- **配置备份**：备份当前配置
- **配置应用**：应用新配置
- **配置验证**：验证新配置的正确性
- **服务重载**：重新加载服务配置

#### 进程清理操作（cleanup）
- **进程识别**：识别需要清理的进程
- **进程状态检查**：检查进程的当前状态
- **优雅终止**：尝试优雅终止进程
- **强制终止**：如果优雅终止失败，强制终止进程
- **资源清理**：清理进程占用的资源

#### 数据恢复操作（recover）
- **恢复点识别**：识别可用的恢复点
- **恢复点验证**：验证恢复点的完整性
- **数据备份**：备份当前数据
- **数据恢复**：执行数据恢复操作
- **恢复验证**：验证恢复的数据

### 4. 效果验证阶段
- **状态检查**：检查修复后的系统状态
- **功能测试**：测试修复目标的核心功能
- **性能验证**：验证修复后的性能表现
- **错误检查**：检查是否有新的错误产生
- **健康检查**：执行全面的健康检查

### 5. 回滚准备阶段（始终准备）
- **回滚计划**：为每个操作步骤准备回滚计划
- **回滚检查点**：创建操作检查点，支持部分回滚
- **回滚触发器**：设置回滚触发条件
- **回滚资源**：准备回滚所需的资源

### 6. 结果生成阶段
- **结果组装**：将修复结果组装为统一结构
- **效果评估**：评估修复操作的效果
- **风险总结**：总结修复过程中的风险情况
- **经验记录**：记录修复操作的经验教训
- **资源清理**：清理临时文件和中间数据
- **输出生成**：按指定格式生成最终输出

## 输出格式

### 成功输出格式

```json
{
  "status": "success",
  "session_id": "controlled-repair-session-001",
  "execution_time": 45.2,
  "results": {
    "summary": {
      "repair_action": "restart",
      "repair_target": "nginx.service",
      "repair_status": "completed",
      "risk_level": "low",
      "approval_required": false,
      "approval_granted": true,
      "backup_created": true,
      "rollback_prepared": true,
      "verification_passed": true,
      "start_time": "2026-02-03T17:30:00Z",
      "end_time": "2026-02-03T17:30:45Z"
    },
    "execution_details": {
      "phases": {
        "initialization": {
          "status": "completed",
          "duration_seconds": 2.1,
          "permission_check": "passed",
          "risk_assessment": {
            "level": "low",
            "factors": ["常规服务重启", "非关键时段", "有完整备份"]
          }
        },
        "safety_control": {
          "status": "completed",
          "duration_seconds": 3.5,
          "target_locked": true,
          "pre_checks_passed": true,
          "emergency_plan_ready": true
        },
        "repair_execution": {
          "status": "completed",
          "duration_seconds": 25.8,
          "steps": [
            {
              "name": "service_status_check",
              "status": "completed",
              "result": "service_running"
            },
            {
              "name": "graceful_stop",
              "status": "completed",
              "result": "service_stopped",
              "duration_seconds": 5.2
            },
            {
              "name": "service_start",
              "status": "completed",
              "result": "service_started",
              "duration_seconds": 8.5
            }
          ]
        },
        "verification": {
          "status": "completed",
          "duration_seconds": 10.2,
          "checks": [
            {
              "name": "service_status",
              "status": "passed",
              "result": "active (running)"
            },
            {
              "name": "port_listening",
              "status": "passed",
              "result": "port_80_listening"
            },
            {
              "name": "http_response",
              "status": "passed",
              "result": "http_200_ok"
            }
          ]
        }
      },
      "backup_info": {
        "created": true,
        "location": "/var/backups/witty-diagnosis/nginx-20260203-173000.tar.gz",
        "size_mb": 12.5,
        "integrity_verified": true
      },
      "rollback_info": {
        "prepared": true,
        "checkpoints": 3,
        "rollback_plan": {
          "steps": [
            "restore_backup",
            "restart_service",
            "verify_restoration"
          ],
          "estimated_time_seconds": 30
        }
      }
    },
    "performance": {
      "total_duration_seconds": 45.2,
      "phase_breakdown": {
        "initialization": 2.1,
        "safety_control": 3.5,
        "repair_execution": 25.8,
        "verification": 10.2,
        "cleanup": 3.6
      },
      "resource_usage": {
        "cpu_percent": 15.2,
        "memory_mb": 128,
        "disk_io_mb": 45.8
      }
    }
  },
  "metadata": {
    "skill_name": "controlled-repair",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:45Z",
    "execution_mode": "standard",
    "data_format_version": "1.0.0"
  }
}
```

### 部分成功输出格式

```json
{
  "status": "partial",
  "session_id": "controlled-repair-session-002",
  "execution_time": 35.1,
  "results": {
    "summary": {
      "repair_action": "reconfigure",
      "repair_target": "/etc/nginx/nginx.conf",
      "repair_status": "partial",
      "risk_level": "medium",
      "verification_passed": false,
      "issues_found": 1
    },
    "execution_details": {
      "phases": {
        "repair_execution": {
          "status": "completed",
          "steps": [...]
        },
        "verification": {
          "status": "failed",
          "failed_checks": [
            {
              "name": "config_syntax",
              "status": "failed",
              "error": "nginx: configuration file /etc/nginx/nginx.conf test failed",
              "details": "unknown directive 'server_nam' in /etc/nginx/nginx.conf:15"
            }
          ]
        }
      }
    },
    "partial_results": {
      "successful_phases": ["initialization", "safety_control", "repair_execution"],
      "failed_phases": ["verification"],
      "rollback_executed": true,
      "rollback_status": "success",
      "original_state_restored": true
    }
  },
  "metadata": {
    "skill_name": "controlled-repair",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:35Z"
  }
}
```

### 错误输出格式

```json
{
  "status": "error",
  "session_id": "controlled-repair-session-003",
  "execution_time": 8.5,
  "error_code": "PERMISSION_DENIED",
  "error_message": "执行用户权限不足，无法重启系统服务",
  "details": {
    "failed_step": "权限检查阶段",
    "failed_phase": "initialization",
    "error_context": {
      "required_permission": "root或sudo权限",
      "current_user": "appuser",
      "target_service": "nginx.service",
      "suggested_action": "使用sudo执行或联系系统管理员"
    }
  },
  "suggestions": [
    "使用具有适当权限的用户执行修复操作",
    "配置sudo权限允许重启nginx服务",
    "联系系统管理员获取必要权限"
  ],
  "rollback_info": {
    "rollback_attempted": false,
    "reason": "修复操作未开始执行，无需回滚"
  },
  "metadata": {
    "skill_name": "controlled-repair",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:08Z"
  }
}
```

### 输出字段说明

| 字段名 | 类型 | 必需 | 描述 |
|--------|------|------|------|
| `status` | string | 是 | 执行状态：`"success"`, `"partial"`, `"error"` |
| `session_id` | string | 是 | 诊断会话ID |
| `execution_time` | number | 是 | 执行时间（秒） |
| `results.summary` | object | 是 | 修复结果摘要信息 |
| `results.execution_details` | object | 是 | 详细的执行过程信息 |
| `results.performance` | object | 否 | 执行过程性能指标 |
| `results.partial_results` | object | 否 | 部分成功时的详细信息 |
| `metadata` | object | 是 | 元数据信息 |
| `error_code` | string | 否 | 错误代码（仅错误时） |
| `error_message` | string | 否 | 错误描述（仅错误时） |
| `details` | object | 否 | 详细错误信息（仅错误时） |
| `suggestions` | array | 否 | 修复建议（仅错误时） |
| `rollback_info` | object | 否 | 回滚相关信息 |

## 示例

### 示例1：安全重启Web服务

**场景描述**：
生产环境的nginx Web服务出现内存泄漏，需要安全重启服务。要求在业务低峰期执行，确保服务中断时间最短。

**命令调用**：
```bash
claude witty-diagnosis:controlled-repair --target service --repair-action restart --repair-target nginx.service --require-approval false --backup-before-repair true
```

**输入数据**：
```json
{
  "session_id": "web-service-restart-001",
  "target": "service",
  "repair_action": "restart",
  "repair_target": "nginx.service",
  "parameters": {
    "timeout": 180,
    "verbosity": "info",
    "require_approval": false,
    "auto_rollback": true,
    "rollback_timeout": 60,
    "verification_interval": 3,
    "verification_attempts": 5,
    "risk_threshold": "low",
    "dry_run": false,
    "backup_before_repair": true,
    "backup_location": "/var/backups/witty-diagnosis"
  },
  "metadata": {
    "request_id": "req-web-001",
    "environment": "production",
    "time_window": "maintenance",
    "user": {
      "id": "admin",
      "role": "system-admin"
    },
    "diagnosis_result": {
      "root_cause": "nginx worker进程内存泄漏",
      "confidence": 0.92,
      "recommended_action": "重启nginx服务释放内存"
    }
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "web-service-restart-001",
  "execution_time": 32.5,
  "results": {
    "summary": {
      "repair_action": "restart",
      "repair_target": "nginx.service",
      "repair_status": "completed",
      "risk_level": "low",
      "approval_required": false,
      "backup_created": true,
      "rollback_prepared": true,
      "verification_passed": true,
      "service_downtime_seconds": 8.7
    },
    "execution_details": {
      "phases": {
        "repair_execution": {
          "steps": [
            {
              "name": "graceful_stop",
              "status": "completed",
              "result": "service_stopped",
              "duration_seconds": 5.2
            },
            {
              "name": "service_start",
              "status": "completed",
              "result": "service_started",
              "duration_seconds": 3.5
            }
          ]
        },
        "verification": {
          "checks": [
            {
              "name": "service_status",
              "status": "passed",
              "result": "active (running)"
            },
            {
              "name": "http_response",
              "status": "passed",
              "result": "http_200_ok",
              "response_time_ms": 45
            }
          ]
        }
      }
    }
  },
  "metadata": {
    "skill_name": "controlled-repair",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T02:30:00Z"
  }
}
```

### 示例2：配置回滚操作

**场景描述**：
数据库配置更新后导致性能下降，需要回滚到之前的稳定配置。要求验证回滚后的配置正确性。

**命令调用**：
```bash
claude witty-diagnosis:controlled-repair --target config --repair-action rollback --repair-target /etc/mysql/my.cnf --verification-attempts 5 --risk-threshold medium
```

**输入数据**：
```json
{
  "session_id": "db-config-rollback-001",
  "target": "config",
  "repair_action": "rollback",
  "repair_target": "/etc/mysql/my.cnf",
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    "require_approval": true,
    "auto_rollback": true,
    "verification_interval": 10,
    "verification_attempts": 5,
    "risk_threshold": "medium",
    "backup_before_repair": true,
    "backup_location": "/var/backups/witty-diagnosis/mysql"
  },
  "metadata": {
    "request_id": "req-db-001",
    "environment": "production",
    "issue_description": "MySQL配置更新后查询性能下降50%",
    "priority": "high",
    "user": {
      "id": "dba",
      "role": "database-admin"
    }
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "db-config-rollback-001",
  "execution_time": 65.8,
  "results": {
    "summary": {
      "repair_action": "rollback",
      "repair_target": "/etc/mysql/my.cnf",
      "repair_status": "completed",
      "risk_level": "medium",
      "approval_required": true,
      "approval_granted": true,
      "backup_created": true,
      "rollback_prepared": true,
      "verification_passed": true,
      "backup_used": "mysql-config-20260202-180000.tar.gz"
    },
    "execution_details": {
      "phases": {
        "repair_execution": {
          "steps": [
            {
              "name": "backup_find",
              "status": "completed",
              "result": "backup_found",
              "backup_file": "mysql-config-20260202-180000.tar.gz",
              "backup_time": "2026-02-02T18:00:00Z"
            },
            {
              "name": "config_restore",
              "status": "completed",
              "result": "config_restored",
              "original_config_backed_up": true
            },
            {
              "name": "service_reload",
              "status": "completed",
              "result": "service_reloaded",
              "duration_seconds": 12.5
            }
          ]
        },
        "verification": {
          "checks": [
            {
              "name": "config_syntax",
              "status": "passed",
              "result": "syntax_ok"
            },
            {
              "name": "service_status",
              "status": "passed",
              "result": "active (running)"
            },
            {
              "name": "query_test",
              "status": "passed",
              "result": "query_executed",
              "response_time_ms": 120
            }
          ]
        }
      }
    }
  },
  "metadata": {
    "skill_name": "controlled-repair",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

## 注意事项

### 安全注意事项
- **权限最小化**：使用最小必要权限执行修复操作，避免过度授权
- **操作审批**：高风险操作必须经过人工审批，审批记录需完整保存
- **敏感信息保护**：修复过程中涉及的敏感信息（如密码、密钥）必须加密处理
- **操作审计**：所有修复操作必须记录详细审计日志，包括操作者、时间、操作内容
- **网络隔离**：修复关键系统时，建议先进行网络隔离，防止影响扩大
- **双重确认**：关键操作前要求双重确认，防止误操作

### 性能注意事项
- **业务影响**：评估修复操作对业务的影响，选择业务低峰期执行
- **资源预留**：确保系统有足够的资源（CPU、内存、磁盘）执行修复操作
- **超时控制**：设置合理的超时时间，防止操作卡死影响系统
- **并发限制**：同一时间只允许一个修复操作执行，避免资源竞争
- **回滚性能**：回滚操作应比原操作更快，确保快速恢复

### 环境要求
- **操作系统**：欧拉OS 2.0或更高版本，兼容其他Linux发行版
- **权限要求**：根据修复目标需要相应的系统权限
- **备份空间**：需要足够的磁盘空间存储备份文件
- **网络连通性**：需要网络连通性进行效果验证
- **监控系统**：建议集成监控系统，实时监控修复过程

### 限制和约束
- **操作范围**：只能修复本地系统，不支持远程修复
- **回滚限制**：某些操作可能无法完全回滚（如数据删除）
- **时间窗口**：生产环境修复需在维护窗口内执行
- **依赖关系**：复杂系统的修复可能涉及多个组件的依赖关系
- **知识库依赖**：最佳修复方案依赖知识库中的经验积累

## 测试用例

### 测试1：服务重启安全测试
- **测试目的**：验证服务重启操作的安全性和可靠性
- **输入数据**：请求重启一个测试服务（如nginx测试实例）
- **预期输出**：成功状态，服务正常重启，验证通过
- **验证点**：
  - 服务优雅停止和启动
  - 备份创建和验证
  - 回滚计划准备
  - 效果验证全面
  - 执行时间在预期范围内

### 测试2：配置回滚测试
- **测试目的**：验证配置回滚操作的完整流程
- **输入数据**：请求回滚一个测试配置文件
- **预期输出**：成功状态，配置正确回滚，验证通过
- **验证点**：
  - 备份查找和验证
  - 当前配置备份
  - 配置恢复正确性
  - 服务重载验证
  - 回滚完整性检查

### 测试3：高风险操作审批测试
- **测试目的**：验证高风险操作的审批流程
- **输入数据**：请求执行高风险操作，设置require_approval=true
- **预期输出**：等待审批状态或审批后执行
- **验证点**：
  - 风险评估正确性
  - 审批流程触发
  - 审批记录完整性
  - 未审批时操作阻塞

### 测试4：修复失败回滚测试
- **测试目的**：验证操作失败时的自动回滚机制
- **输入数据**：请求执行一个会失败的操作（如无效配置）
- **预期输出**：错误状态，自动回滚执行，原始状态恢复
- **验证点**：
  - 错误检测及时性
  - 回滚触发正确性
  - 回滚执行完整性
  - 原始状态恢复验证

### 测试5：权限不足错误处理测试
- **测试目的**：验证权限不足时的优雅处理
- **输入数据**：使用非特权用户请求需要特权的操作
- **预期输出**：权限错误状态，清晰的错误信息和建议
- **验证点**：
  - 权限检查准确性
  - 错误信息清晰度
  - 修复建议实用性
  - 资源清理完整性

### 测试6：效果验证失败测试
- **测试目的**：验证效果验证失败时的处理
- **输入数据**：请求修复但设置会失败的验证条件
- **预期输出**：部分成功状态，回滚执行，详细的问题报告
- **验证点**：
  - 验证失败检测
  - 问题诊断准确性
  - 回滚执行正确性
  - 问题报告完整性

## 相关技能

### 前置技能
- **root-cause-analysis**：提供修复操作的依据和推荐方案
- **data-collector**：提供修复前的系统状态数据
- **fault-localization**：定位需要修复的具体目标

### 后置技能
- **intelligent-inspection**：修复后定期检查修复效果
- **knowledge-base**：将修复经验记录到知识库
- **metric-analyzer**：监控修复后的系统性能指标

### 替代技能
- 无直接替代技能，但可以与其他自动化运维工具（如Ansible、Chef）配合使用

### 补充技能
- **config-manager**：管理修复操作的配置和策略
- **log-analyzer**：分析修复过程中的日志信息
- **trace-analyzer**：跟踪修复操作的影响链

## 更新日志

### 版本 1.0.0 (2026-02-03)
- 初始版本发布
- 实现五大修复操作：重启、回滚、重配置、清理、恢复
- 完整的安全控制流程：权限检查、风险评估、操作审批
- 完善的回滚机制：自动回滚、回滚计划、状态恢复
- 全面的效果验证：状态检查、功能测试、性能验证
- 符合项目数据格式规范
- 包含全面的测试用例

### 版本 1.1.0 (计划中)
- 添加批量修复操作支持
- 支持修复操作模板和复用
- 增强风险评估模型
- 添加修复操作调度功能
- 支持修复操作依赖管理

### 版本 1.2.0 (计划中)
- 添加机器学习驱动的修复建议
- 支持修复操作效果预测
- 增强跨系统修复能力
- 添加修复操作模拟和演练
- 支持修复操作知识图谱

---

*文档版本：1.0.0*
*最后更新：2026-02-03*