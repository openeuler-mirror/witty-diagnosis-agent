---
name: intelligent-inspection
description: 智能巡检技能，负责主动发现系统潜在问题，进行异常模式识别，生成巡检报告和趋势分析
version: 1.0.0
category: core
author: witty-diagnosis-team
created: 2026-02-03
updated: 2026-02-03
tags:
  - inspection
  - monitoring
  - anomaly-detection
  - trend-analysis
  - proactive-diagnostics
  - euler-os
  - system-health
requires:
  - witty-diagnosis:data-collector
  - witty-diagnosis:metric-analyzer
  - witty-diagnosis:log-analyzer
---

# 智能巡检 - 主动式系统健康检查技能

## 概述

智能巡检技能是witty-diagnosis-agent项目的核心巡检组件，专门设计用于对欧拉OS系统进行主动、智能的巡检检查。本技能通过多维度数据收集、智能分析和趋势预测，主动发现系统潜在问题，提供全面的健康状态评估和预警建议。

主要功能包括：
1. **巡检策略定义**：支持自定义巡检策略和计划，包括巡检频率、深度和范围
2. **异常模式识别**：使用智能算法识别系统中的异常模式和潜在风险
3. **巡检报告生成**：生成详细、易读的巡检报告，包含问题描述、严重程度和建议措施
4. **趋势分析**：分析系统性能趋势，预测未来可能出现的问题
5. **预警生成**：基于分析结果生成预警信息，支持多种通知方式
6. **健康评分**：提供系统健康评分，量化系统健康状态

本技能是主动运维的关键组件，适用于日常巡检、性能监控、容量规划和安全检查等多种场景。

## 使用时机

### 应该使用此技能的情况：
- 需要进行定期系统健康检查时
- 系统上线前或重大变更后的验证检查
- 性能下降或异常现象出现前的预防性检查
- 容量规划和资源优化前的现状评估
- 安全合规性检查和漏洞扫描
- 建立系统健康基线和趋势分析
- 与其他诊断技能配合进行深度分析

### 不应该使用此技能的情况：
- 实时故障诊断（使用fault-localization技能）
- 深度日志分析（使用log-analyzer技能）
- 性能指标详细分析（使用metric-analyzer技能）
- 紧急故障恢复（使用controlled-repair技能）

## 输入要求

### 必需输入

| 参数名 | 类型 | 描述 | 示例值 |
|--------|------|------|--------|
| `session_id` | string | 巡检会话ID | `"inspection-001"` |
| `inspection_type` | string | 巡检类型 | `"daily"`, `"weekly"`, `"performance"`, `"security"`, `"comprehensive"` |

### 可选输入

| 参数名 | 类型 | 默认值 | 描述 |
|--------|------|--------|------|
| `timeout` | number | `600` | 执行超时时间（秒） |
| `verbosity` | string | `"info"` | 日志详细程度：`"debug"`, `"info"`, `"warn"`, `"error"` |
| `inspection_depth` | string | `"standard"` | 巡检深度：`"quick"`, `"standard"`, `"deep"`, `"exhaustive"` |
| `check_categories` | array | `["system", "performance", "security", "storage", "network"]` | 检查类别列表 |
| `alert_threshold` | object | `{"critical": 90, "warning": 70, "info": 50}` | 告警阈值配置 |
| `trend_analysis_days` | number | `7` | 趋势分析天数 |
| `generate_report` | boolean | `true` | 是否生成详细报告 |
| `send_alerts` | boolean | `false` | 是否发送告警通知 |
| `compare_with_baseline` | boolean | `true` | 是否与基线比较 |
| `output_format` | string | `"json"` | 输出格式：`"json"`, `"yaml"`, `"html"`, `"text"` |

### 输入格式示例

```json
{
  "session_id": "inspection-session-001",
  "inspection_type": "comprehensive",
  "parameters": {
    "timeout": 600,
    "verbosity": "info",
    "inspection_depth": "deep",
    "check_categories": [
      "system",
      "performance",
      "security",
      "storage",
      "network",
      "application"
    ],
    "alert_threshold": {
      "critical": 90,
      "warning": 70,
      "info": 50
    },
    "trend_analysis_days": 14,
    "generate_report": true,
    "send_alerts": false,
    "compare_with_baseline": true,
    "output_format": "json"
  },
  "metadata": {
    "request_id": "req-inspection-001",
    "timestamp": "2026-02-03T09:00:00Z",
    "environment": "production",
    "scheduled": true,
    "schedule_name": "daily-morning-check"
  }
}
```

## 执行步骤

### 1. 初始化阶段
- **参数验证**：验证输入参数的有效性和完整性
- **策略加载**：根据inspection_type和inspection_depth加载相应的巡检策略
- **依赖检查**：检查data-collector、metric-analyzer等依赖技能的可用性
- **环境准备**：创建巡检工作目录，初始化日志和结果存储
- **基线获取**：从knowledge-base获取系统基线数据（如配置）
- **资源评估**：评估系统当前负载，确定巡检强度

### 2. 数据收集阶段
调用相关技能收集巡检所需数据：
- **系统数据收集**：调用data-collector收集系统状态数据
- **性能数据收集**：调用metric-analyzer收集性能指标和历史趋势
- **日志数据收集**：调用log-analyzer收集和分析关键日志
- **配置数据收集**：收集系统配置和安全策略
- **应用状态收集**：收集关键应用的健康状态

### 3. 分析检测阶段
对收集的数据进行多维度分析：

#### 系统健康检查
- **资源使用分析**：CPU、内存、磁盘、网络使用率分析
- **服务状态检查**：关键系统服务的运行状态
- **进程健康检查**：关键进程的资源使用和稳定性
- **系统负载分析**：系统负载趋势和峰值分析

#### 性能分析
- **性能瓶颈识别**：识别CPU、内存、IO、网络瓶颈
- **响应时间分析**：分析系统响应时间趋势
- **容量规划分析**：基于历史趋势预测资源需求
- **性能异常检测**：使用统计方法检测性能异常

#### 安全检查
- **安全配置检查**：检查防火墙、SELinux、SSH等安全配置
- **漏洞扫描**：检查已知安全漏洞和补丁状态
- **用户权限检查**：检查用户权限和访问控制
- **安全日志分析**：分析安全相关日志事件

#### 存储检查
- **磁盘空间分析**：分析磁盘使用情况和增长趋势
- **文件系统检查**：检查文件系统完整性和错误
- **IO性能分析**：分析磁盘IO性能和瓶颈
- **备份状态检查**：检查备份策略和执行状态

#### 网络检查
- **网络连通性**：检查网络连接和延迟
- **端口安全**：检查开放端口和服务安全
- **网络性能**：分析网络带宽使用和性能
- **DNS和路由**：检查DNS解析和路由配置

### 4. 智能分析阶段
- **异常模式识别**：使用机器学习算法识别异常模式
- **关联分析**：分析不同问题之间的关联关系
- **根因推断**：基于分析结果推断问题根因
- **趋势预测**：基于历史数据预测未来趋势
- **风险评估**：评估发现问题的风险等级和影响范围

### 5. 结果生成阶段
- **问题汇总**：汇总所有发现的问题和建议
- **健康评分**：计算系统整体健康评分
- **报告生成**：生成详细巡检报告
- **预警生成**：根据阈值生成预警信息
- **基线更新**：更新系统健康基线
- **资源清理**：清理临时文件和中间数据

## 输出格式

### 成功输出格式

```json
{
  "status": "success",
  "session_id": "inspection-session-001",
  "execution_time": 245.8,
  "results": {
    "summary": {
      "inspection_type": "comprehensive",
      "inspection_depth": "deep",
      "start_time": "2026-02-03T09:00:00Z",
      "end_time": "2026-02-03T09:04:06Z",
      "total_checks": 156,
      "passed_checks": 142,
      "failed_checks": 8,
      "warning_checks": 6,
      "health_score": 88.5,
      "overall_status": "healthy"
    },
    "health_score_breakdown": {
      "system": 92.0,
      "performance": 85.5,
      "security": 95.0,
      "storage": 82.0,
      "network": 88.0,
      "application": 90.5
    },
    "issues": {
      "critical": [
        {
          "id": "ISSUE-001",
          "category": "storage",
          "description": "根分区磁盘使用率超过90%",
          "severity": "critical",
          "impact": "系统可能因磁盘空间不足而崩溃",
          "root_cause": "日志文件未及时清理",
          "recommendation": "清理/var/log目录下的旧日志文件",
          "immediate_action": "执行日志轮转和清理",
          "long_term_solution": "配置日志自动轮转策略",
          "affected_components": ["/dev/sda1", "/var/log"],
          "detected_time": "2026-02-03T09:02:30Z",
          "confidence": 0.95
        }
      ],
      "warning": [
        {
          "id": "ISSUE-002",
          "category": "performance",
          "description": "内存使用率持续上升趋势",
          "severity": "warning",
          "impact": "可能在未来24小时内出现内存不足",
          "root_cause": "应用内存泄漏",
          "recommendation": "监控应用内存使用，重启有问题的服务",
          "affected_components": ["java-app-1", "memory"],
          "trend_data": {
            "current": 78.5,
            "24h_ago": 72.3,
            "trend": "increasing",
            "predicted_24h": 85.2
          },
          "confidence": 0.82
        }
      ],
      "info": [
        {
          "id": "ISSUE-003",
          "category": "security",
          "description": "SSH协议版本1仍被启用",
          "severity": "info",
          "impact": "安全风险较低，但建议升级",
          "recommendation": "在/etc/ssh/sshd_config中禁用SSHv1",
          "affected_components": ["sshd_config"],
          "confidence": 1.0
        }
      ]
    },
    "trend_analysis": {
      "performance_trends": {
        "cpu_usage": {
          "current": 45.2,
          "7d_avg": 42.8,
          "trend": "stable",
          "prediction_7d": 46.5
        },
        "memory_usage": {
          "current": 78.5,
          "7d_avg": 75.2,
          "trend": "increasing",
          "prediction_7d": 82.3
        },
        "disk_usage": {
          "current": 85.3,
          "7d_avg": 83.7,
          "trend": "increasing",
          "prediction_7d": 87.8
        }
      },
      "anomaly_detection": {
        "total_anomalies": 3,
        "anomaly_details": [
          {
            "metric": "disk_iops",
            "timestamp": "2026-02-03T08:45:00Z",
            "value": 1250,
            "expected_range": "300-800",
            "deviation": 56.25
          }
        ]
      }
    },
    "recommendations": {
      "immediate": [
        "清理/var/log目录，释放至少5GB磁盘空间",
        "重启java-app-1服务以释放内存"
      ],
      "short_term": [
        "配置日志自动轮转策略",
        "监控内存泄漏应用"
      ],
      "long_term": [
        "考虑增加磁盘容量",
        "优化应用内存使用"
      ]
    },
    "baseline_comparison": {
      "compared_with": "baseline-2026-01-27",
      "changes_detected": 12,
      "significant_changes": 3,
      "change_details": [
        {
          "component": "memory_usage",
          "current": 78.5,
          "baseline": 72.3,
          "change_percent": 8.6,
          "significance": "high"
        }
      ]
    },
    "performance_metrics": {
      "data_collection_time": 45.2,
      "analysis_time": 120.8,
      "report_generation_time": 79.8,
      "total_checks_executed": 156,
      "checks_per_second": 0.63,
      "memory_usage_mb": 512,
      "cpu_usage_percent": 35.2
    }
  },
  "metadata": {
    "skill_name": "intelligent-inspection",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T09:04:06Z",
    "execution_mode": "scheduled",
    "report_id": "inspection-report-20260203-0900",
    "data_format_version": "1.0.0"
  }
}
```

### 部分成功输出格式

```json
{
  "status": "partial",
  "session_id": "inspection-session-002",
  "execution_time": 180.5,
  "results": {
    "summary": {
      "inspection_type": "comprehensive",
      "total_checks": 156,
      "completed_checks": 142,
      "failed_checks": 8,
      "skipped_checks": 6,
      "health_score": 85.2,
      "overall_status": "degraded"
    },
    "partial_results": {
      "completed_categories": ["system", "performance", "storage"],
      "failed_categories": ["security", "network"],
      "failure_reasons": {
        "security": "权限不足，无法访问安全配置",
        "network": "网络检查超时"
      }
    },
    "issues": {
      // 已完成检查的问题
    }
  },
  "metadata": {
    "skill_name": "intelligent-inspection",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T09:03:00Z"
  }
}
```

### 错误输出格式

```json
{
  "status": "error",
  "session_id": "inspection-session-003",
  "execution_time": 25.1,
  "error_code": "DEPENDENCY_UNAVAILABLE",
  "error_message": "依赖技能data-collector不可用",
  "details": {
    "failed_step": "初始化阶段",
    "failed_dependency": "witty-diagnosis:data-collector",
    "error_context": {
      "dependency_status": "not_responding",
      "attempted_retries": 3,
      "timeout_seconds": 30
    }
  },
  "suggestions": [
    "检查data-collector技能是否已正确安装",
    "验证data-collector技能的服务状态",
    "检查网络连接和权限配置",
    "尝试使用简化巡检模式（不依赖data-collector）"
  ],
  "metadata": {
    "skill_name": "intelligent-inspection",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T09:00:25Z"
  }
}
```

### 输出字段说明

| 字段名 | 类型 | 必需 | 描述 |
|--------|------|------|------|
| `status` | string | 是 | 执行状态：`"success"`, `"partial"`, `"error"` |
| `session_id` | string | 是 | 巡检会话ID |
| `execution_time` | number | 是 | 执行时间（秒） |
| `results.summary` | object | 是 | 巡检结果摘要信息 |
| `results.health_score_breakdown` | object | 是 | 各维度健康评分 |
| `results.issues` | object | 是 | 发现的问题分类 |
| `results.trend_analysis` | object | 否 | 趋势分析结果 |
| `results.recommendations` | object | 是 | 改进建议 |
| `results.baseline_comparison` | object | 否 | 基线比较结果 |
| `results.performance_metrics` | object | 否 | 巡检过程性能指标 |
| `results.partial_results` | object | 否 | 部分成功时的详细信息 |
| `metadata` | object | 是 | 元数据信息 |
| `error_code` | string | 否 | 错误代码（仅错误时） |
| `error_message` | string | 否 | 错误描述（仅错误时） |
| `details` | object | 否 | 详细错误信息（仅错误时） |
| `suggestions` | array | 否 | 修复建议（仅错误时） |

## 示例

### 示例1：日常快速巡检

**场景描述**：
对生产服务器进行日常快速健康检查，重点关注关键指标。

**命令调用**：
```bash
claude witty-diagnosis:intelligent-inspection --inspection-type daily --inspection-depth quick --check-categories system performance
```

**输入数据**：
```json
{
  "session_id": "daily-quick-check-001",
  "inspection_type": "daily",
  "parameters": {
    "timeout": 300,
    "inspection_depth": "quick",
    "check_categories": ["system", "performance"],
    "alert_threshold": {
      "critical": 90,
      "warning": 80
    },
    "generate_report": true,
    "output_format": "json"
  },
  "metadata": {
    "request_id": "req-daily-001",
    "environment": "production",
    "scheduled": true,
    "schedule_name": "daily-quick-check"
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "daily-quick-check-001",
  "execution_time": 85.2,
  "results": {
    "summary": {
      "inspection_type": "daily",
      "inspection_depth": "quick",
      "total_checks": 42,
      "passed_checks": 40,
      "failed_checks": 1,
      "warning_checks": 1,
      "health_score": 92.8,
      "overall_status": "healthy"
    },
    "health_score_breakdown": {
      "system": 95.0,
      "performance": 90.5
    },
    "issues": {
      "warning": [
        {
          "id": "PERF-001",
          "category": "performance",
          "description": "CPU使用率接近警告阈值",
          "severity": "warning",
          "current_value": 78.5,
          "threshold": 80.0,
          "recommendation": "监控CPU使用趋势，考虑优化或扩容"
        }
      ]
    },
    "recommendations": {
      "immediate": [],
      "short_term": ["监控CPU使用趋势"],
      "long_term": []
    }
  },
  "metadata": {
    "skill_name": "intelligent-inspection",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T09:00:00Z"
  }
}
```

### 示例2：深度性能巡检

**场景描述**：
针对性能问题进行深度巡检，包括趋势分析和容量规划。

**命令调用**：
```bash
claude witty-diagnosis:intelligent-inspection --inspection-type performance --inspection-depth deep --trend-analysis-days 30 --check-categories performance storage
```

**输入数据**：
```json
{
  "session_id": "performance-deep-check-001",
  "inspection_type": "performance",
  "parameters": {
    "timeout": 900,
    "inspection_depth": "deep",
    "check_categories": ["performance", "storage"],
    "trend_analysis_days": 30,
    "alert_threshold": {
      "critical": 85,
      "warning": 70
    },
    "generate_report": true,
    "compare_with_baseline": true,
    "output_format": "html"
  },
  "metadata": {
    "request_id": "req-perf-001",
    "issue_description": "应用响应时间变慢",
    "priority": "high",
    "environment": "production"
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "performance-deep-check-001",
  "execution_time": 420.5,
  "results": {
    "summary": {
      "inspection_type": "performance",
      "inspection_depth": "deep",
      "total_checks": 78,
      "passed_checks": 72,
      "failed_checks": 4,
      "warning_checks": 2,
      "health_score": 84.6,
      "overall_status": "degraded"
    },
    "trend_analysis": {
      "performance_trends": {
        "disk_iops": {
          "current": 1250,
          "30d_avg": 850,
          "trend": "sharply_increasing",
          "prediction_7d": 1450,
          "capacity_limit": 2000,
          "days_to_limit": 14
        },
        "memory_usage": {
          "current": 82.3,
          "30d_avg": 75.8,
          "trend": "increasing",
          "prediction_7d": 85.5
        }
      }
    },
    "issues": {
      "critical": [
        {
          "id": "PERF-CRIT-001",
          "category": "storage",
          "description": "磁盘IOPS持续快速增长，预计14天内达到上限",
          "severity": "critical",
          "root_cause": "数据库索引碎片化导致IO增加",
          "recommendation": "优化数据库索引，考虑SSD升级",
          "capacity_planning": {
            "current_usage": "62.5%",
            "growth_rate": "4.5%/day",
            "time_to_limit": "14天"
          }
        }
      ]
    },
    "capacity_planning": {
      "recommendations": [
        "立即开始数据库索引优化",
        "14天内升级存储为SSD",
        "增加内存容量以缓解IO压力"
      ],
      "timeline": {
        "immediate": ["数据库优化"],
        "1_week": ["监控优化效果"],
        "2_weeks": ["存储升级准备"],
        "1_month": ["完成升级和验证"]
      }
    }
  },
  "metadata": {
    "skill_name": "intelligent-inspection",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T10:00:00Z",
    "report_url": "/reports/performance-deep-check-001.html"
  }
}
```

## 注意事项

### 安全注意事项
- **权限管理**：需要适当的系统权限来执行全面巡检，建议使用专用服务账户
- **敏感数据处理**：自动过滤配置文件中的敏感信息（密码、密钥等）
- **审计日志**：所有巡检操作都会记录详细的审计日志
- **访问控制**：支持基于角色的访问控制，限制敏感检查的执行
- **数据加密**：巡检报告和结果数据支持加密存储和传输

### 性能注意事项
- **资源消耗**：深度巡检会消耗较多系统资源，建议在业务低峰期执行
- **执行时间**：全面巡检可能需要5-10分钟，深度巡检可能需要15-30分钟
- **并发限制**：不建议在同一系统上同时执行多个深度巡检
- **数据存储**：趋势分析需要存储历史数据，需考虑存储空间
- **网络影响**：网络检查可能对网络性能产生短暂影响

### 环境要求
- **操作系统**：欧拉OS 2.0或更高版本，兼容主流Linux发行版
- **依赖技能**：需要data-collector、metric-analyzer、log-analyzer等技能
- **存储空间**：需要存储基线数据和历史趋势，建议至少1GB可用空间
- **时间同步**：需要准确的时间同步以进行趋势分析
- **网络连接**：需要网络连接以获取更新和发送告警

### 限制和约束
- **实时性**：不是实时监控工具，适合定期巡检和趋势分析
- **数据范围**：主要关注系统层面，应用层面检查有限
- **预测精度**：趋势预测基于历史数据，实际可能有所偏差
- **自定义检查**：支持有限的自定义检查规则，复杂规则需要扩展
- **容器环境**：在容器内运行时检查范围受限

## 测试用例

### 测试1：日常快速巡检测试
- **测试目的**：验证日常快速巡检的基本功能
- **输入数据**：日常巡检类型，快速深度，系统性能检查
- **预期输出**：成功状态，健康评分，基本问题检测
- **验证点**：
  - 巡检在5分钟内完成
  - 健康评分计算正确
  - 基本问题检测功能正常
  - 输出格式符合规范

### 测试2：深度全面巡检测试
- **测试目的**：验证深度全面巡检的完整功能
- **输入数据**：全面巡检类型，深度检查，所有检查类别
- **预期输出**：成功状态，详细巡检报告，趋势分析
- **验证点**：
  - 所有检查类别都执行
  - 趋势分析功能正常
  - 详细报告生成正确
  - 性能指标收集完整

### 测试3：异常检测测试
- **测试目的**：验证异常检测和预警功能
- **输入数据**：模拟异常场景（高CPU、低磁盘空间等）
- **预期输出**：正确识别异常，生成相应预警
- **验证点**：
  - 异常正确识别和分类
  - 预警阈值生效
  - 建议措施合理
  - 严重程度评估准确

### 测试4：趋势分析测试
- **测试目的**：验证趋势分析和预测功能
- **输入数据**：包含历史数据的巡检请求
- **预期输出**：趋势分析结果，未来预测
- **验证点**：
  - 趋势识别准确
  - 预测算法合理
  - 容量规划建议有效
  - 基线比较功能正常

### 测试5：错误处理测试
- **测试目的**：验证错误处理和恢复能力
- **输入数据**：无效参数、权限不足、依赖不可用等
- **预期输出**：适当的错误状态和恢复建议
- **验证点**：
  - 优雅的错误处理
  - 清晰的错误信息
  - 有用的恢复建议
  - 资源清理完整

## 相关技能

### 前置技能
- **data-collector**：提供系统数据收集功能
- **metric-analyzer**：提供性能指标分析和历史数据
- **log-analyzer**：提供日志分析和异常检测
- **knowledge-base**：提供基线数据和历史记录

### 后置技能
- **fault-localization**：基于巡检发现的问题进行深度故障定位
- **root-cause-analysis**：对巡检发现的问题进行根因分析
- **controlled-repair**：基于巡检建议执行修复操作
- **config-manager**：更新巡检策略和配置

### 替代技能
- 无直接替代技能，但可以与其他监控系统（如Zabbix、Nagios）配合使用

### 补充技能
- **trace-analyzer**：提供应用层跟踪分析，补充性能巡检
- **security-scanner**：提供专业安全扫描，补充安全检查

## 更新日志

### 版本 1.0.0 (2026-02-03)
- 初始版本发布
- 实现五大检查类别：系统、性能、安全、存储、网络
- 支持四种巡检深度：快速、标准、深度、详尽
- 实现健康评分和趋势分析
- 完整的异常检测和预警功能
- 支持基线比较和历史数据分析
- 符合项目数据格式规范
- 包含全面的测试用例

### 版本 1.1.0 (计划中)
- 添加应用健康检查支持
- 增强机器学习异常检测算法
- 支持自定义检查规则和插件
- 添加实时仪表板和可视化
- 增强容量规划和预测功能
- 支持多节点集群巡检

### 版本 1.2.0 (计划中)
- 添加容器和云环境巡检
- 支持巡检策略模板和共享
- 增强报告定制和导出功能
- 添加巡检工作流和自动化
- 支持巡检结果对比和差异分析
- 增强安全合规性检查

---

*文档版本：1.0.0*
*最后更新：2026-02-03*