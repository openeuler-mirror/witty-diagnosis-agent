---
name: fault-localization
description: 故障定位技能 - 分析故障影响范围，识别受影响的服务和组件
version: 1.0.0
category: core
author: witty-diagnosis-team
created: 2026-02-03
updated: 2026-02-03
tags:
  - fault-analysis
  - impact-assessment
  - service-dependency
  - euler-os
  - diagnosis
---

# 故障定位

## 概述

故障定位技能用于分析系统故障的影响范围，识别受影响的服务、组件和依赖关系。它通过分析服务依赖图、故障传播路径和影响评估，为运维人员提供清晰的故障影响视图，帮助快速确定修复优先级和应急措施。

本技能是诊断流程的核心环节，通常在数据收集和初步分析之后执行，为根因分析和受控修复提供关键输入。

## 使用时机

### 应该使用此技能的情况：
- 系统出现服务中断或性能下降时
- 需要确定故障影响范围和严重程度时
- 多个服务同时出现异常，需要分析关联性时
- 制定故障应急和修复计划时
- 进行故障演练和风险评估时

### 不应该使用此技能的情况：
- 仅需要收集系统数据时（使用data-collector技能）
- 仅需要分析日志时（使用log-analyzer技能）
- 仅需要分析性能指标时（使用metric-analyzer技能）
- 故障原因已明确，仅需要修复时（使用controlled-repair技能）

## 输入要求

### 必需输入

| 参数名 | 类型 | 描述 | 示例值 |
|--------|------|------|--------|
| `session_id` | string | 诊断会话ID | `"fault-localization-001"` |
| `target` | string | 诊断目标，必须是`"system"`或`"service"` | `"system"`, `"service"` |
| `fault_source` | string | 故障源标识（服务名、组件名或IP地址） | `"nginx-service"`, `"database-cluster"`, `"192.168.1.100"` |
| `fault_type` | string | 故障类型 | `"service_down"`, `"performance_degradation"`, `"configuration_error"`, `"resource_exhaustion"` |

### 可选输入

| 参数名 | 类型 | 默认值 | 描述 |
|--------|------|--------|------|
| `timeout` | number | `300` | 执行超时时间（秒） |
| `verbosity` | string | `"info"` | 日志详细程度：`"debug"`, `"info"`, `"warn"`, `"error"` |
| `depth` | number | `3` | 依赖分析深度（1-5） |
| `include_metrics` | boolean | `true` | 是否包含性能指标分析 |
| `dependency_source` | string | `"auto"` | 依赖数据来源：`"auto"`, `"config"`, `"discovery"`, `"manual"` |
| `severity_threshold` | string | `"warning"` | 严重性阈值：`"info"`, `"warning"`, `"critical"` |
| `visualization` | boolean | `false` | 是否生成可视化图表 |

### 输入格式示例

```json
{
  "session_id": "fault-localization-session-001",
  "target": "system",
  "fault_source": "web-server-01",
  "fault_type": "service_down",
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    "depth": 3,
    "include_metrics": true,
    "dependency_source": "auto",
    "severity_threshold": "warning",
    "visualization": true
  },
  "metadata": {
    "request_id": "req-fault-001",
    "timestamp": "2026-02-03T17:30:00Z",
    "environment": "production",
    "user": {
      "id": "ops-user-01",
      "name": "运维人员",
      "role": "operator"
    },
    "context": {
      "incident_id": "INC-20260203-001",
      "priority": "high",
      "business_impact": "customer-facing"
    }
  }
}
```

## 执行步骤

### 1. 初始化阶段
- 验证输入参数的有效性和完整性
- 初始化日志记录器，设置详细级别
- 准备临时工作目录和缓存
- 加载服务依赖模型和配置数据
- 建立与监控系统和配置管理系统的连接

### 2. 故障源分析阶段
- 识别故障源的具体位置和类型
- 收集故障源的当前状态信息
- 分析故障源的配置和运行参数
- 确定故障的初始影响范围
- 评估故障源的恢复时间和难度

### 3. 依赖关系分析阶段
- 构建服务依赖图（从故障源开始）
- 分析直接和间接依赖关系
- 识别关键路径和单点故障
- 评估依赖关系的强度和类型（强依赖/弱依赖）
- 标记循环依赖和复杂依赖关系

### 4. 影响范围评估阶段
- 计算故障传播路径和影响范围
- 评估每个受影响组件的严重程度
- 识别业务关键路径上的组件
- 分析故障的级联效应风险
- 评估数据一致性和完整性影响

### 5. 优先级排序阶段
- 根据业务影响和恢复难度排序
- 识别需要立即处理的组件
- 评估修复操作的依赖关系
- 生成修复建议和应急措施
- 计算总体影响评分

### 6. 结果生成阶段
- 格式化分析结果为标准化输出
- 生成人类可读的影响范围报告
- 创建可视化图表（如果启用）
- 收集执行统计信息和性能指标
- 清理临时文件和资源

## 输出格式

### 成功输出格式

```json
{
  "status": "success",
  "session_id": "fault-localization-session-001",
  "execution_time": 45.8,
  "results": {
    "fault_analysis": {
      "source": {
        "id": "web-server-01",
        "type": "service",
        "status": "down",
        "detected_at": "2026-02-03T17:25:00Z",
        "recovery_estimate": "30分钟"
      },
      "type": "service_down",
      "root_cause_hypothesis": "配置错误导致服务崩溃",
      "confidence": 0.85
    },
    "dependency_graph": {
      "total_nodes": 15,
      "total_edges": 28,
      "direct_dependencies": 3,
      "indirect_dependencies": 12,
      "critical_paths": [
        ["web-server-01", "load-balancer", "api-gateway", "user-service"]
      ]
    },
    "impact_assessment": {
      "affected_services": 8,
      "affected_components": 15,
      "business_impact": "high",
      "overall_severity": "critical",
      "impact_score": 85,
      "estimated_downtime": "2小时",
      "data_risk": "medium"
    },
    "affected_components": [
      {
        "id": "load-balancer",
        "type": "service",
        "dependency_level": 1,
        "impact_severity": "critical",
        "current_status": "degraded",
        "business_importance": "high",
        "recovery_priority": 1,
        "recovery_action": "切换到备用节点",
        "estimated_recovery_time": "10分钟"
      },
      {
        "id": "api-gateway",
        "type": "service",
        "dependency_level": 2,
        "impact_severity": "high",
        "current_status": "operational",
        "business_importance": "high",
        "recovery_priority": 2,
        "recovery_action": "监控性能，准备扩容",
        "estimated_recovery_time": "30分钟"
      },
      {
        "id": "user-service",
        "type": "service",
        "dependency_level": 3,
        "impact_severity": "medium",
        "current_status": "operational",
        "business_importance": "medium",
        "recovery_priority": 3,
        "recovery_action": "增加监控频率",
        "estimated_recovery_time": "1小时"
      }
    ],
    "recommendations": [
      {
        "priority": "immediate",
        "action": "立即切换负载均衡器到备用节点",
        "target": "load-balancer",
        "expected_benefit": "恢复用户访问能力",
        "risk": "low",
        "estimated_time": "10分钟"
      },
      {
        "priority": "short_term",
        "action": "检查web-server-01的配置和日志",
        "target": "web-server-01",
        "expected_benefit": "确定根本原因，防止复发",
        "risk": "medium",
        "estimated_time": "30分钟"
      },
      {
        "priority": "long_term",
        "action": "优化服务依赖，减少单点故障",
        "target": "system-architecture",
        "expected_benefit": "提高系统韧性",
        "risk": "low",
        "estimated_time": "2周"
      }
    ],
    "visualization": {
      "dependency_graph_url": "/tmp/fault-graph-001.png",
      "impact_heatmap_url": "/tmp/impact-heatmap-001.png",
      "timeline_url": "/tmp/recovery-timeline-001.png"
    }
  },
  "metadata": {
    "skill_name": "fault-localization",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z",
    "analysis_depth": 3,
    "dependency_source": "auto",
    "components_analyzed": 25,
    "data_sources": ["service-discovery", "monitoring-system", "config-db"]
  }
}
```

### 错误输出格式

```json
{
  "status": "error",
  "session_id": "fault-localization-session-001",
  "error_code": "DEPENDENCY_DATA_UNAVAILABLE",
  "error_message": "无法获取服务依赖数据，依赖源不可用",
  "details": {
    "failed_step": "依赖关系分析阶段",
    "failed_operation": "从服务发现系统获取依赖数据",
    "error_context": {
      "dependency_source": "discovery",
      "attempt_time": "2026-02-03T17:30:15Z",
      "retry_count": 3,
      "last_error": "Connection refused: service-discovery:8500"
    }
  },
  "suggestions": [
    "检查服务发现系统是否正常运行",
    "尝试使用配置文件作为依赖源（设置dependency_source='config'）",
    "手动提供依赖数据文件",
    "检查网络连接和防火墙规则"
  ],
  "metadata": {
    "skill_name": "fault-localization",
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
| `results.fault_analysis` | object | 是 | 故障源分析结果 |
| `results.dependency_graph` | object | 是 | 依赖关系图信息 |
| `results.impact_assessment` | object | 是 | 总体影响评估 |
| `results.affected_components` | array | 是 | 受影响组件详细列表 |
| `results.recommendations` | array | 是 | 修复建议和优先级 |
| `results.visualization` | object | 否 | 可视化文件路径（如果启用） |
| `metadata` | object | 是 | 元数据信息 |

## 示例

### 示例1：服务故障定位

**场景描述**：
生产环境的web服务突然不可用，需要快速确定影响范围和应急措施。

**命令调用**：
```bash
claude witty-diagnosis:fault-localization --target service --fault-source "web-service-prod" --fault-type "service_down" --depth 3 --visualization
```

**输入数据**：
```json
{
  "session_id": "web-service-fault-001",
  "target": "service",
  "fault_source": "web-service-prod",
  "fault_type": "service_down",
  "parameters": {
    "timeout": 300,
    "depth": 3,
    "visualization": true,
    "severity_threshold": "warning"
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "web-service-fault-001",
  "execution_time": 38.5,
  "results": {
    "fault_analysis": {
      "source": {"id": "web-service-prod", "type": "service", "status": "down"},
      "type": "service_down",
      "root_cause_hypothesis": "内存泄漏导致进程崩溃",
      "confidence": 0.75
    },
    "impact_assessment": {
      "affected_services": 5,
      "overall_severity": "high",
      "impact_score": 70
    },
    "affected_components": [
      {
        "id": "api-gateway",
        "impact_severity": "high",
        "recovery_priority": 1,
        "recovery_action": "路由流量到备用区域"
      }
    ],
    "recommendations": [
      {
        "priority": "immediate",
        "action": "重启web服务并监控内存使用",
        "target": "web-service-prod"
      }
    ]
  },
  "metadata": {
    "skill_name": "fault-localization",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

### 示例2：性能下降影响分析

**场景描述**：
数据库集群出现性能下降，需要分析对上层应用的影响。

**命令调用**：
```bash
claude witty-diagnosis:fault-localization --target system --fault-source "db-cluster-01" --fault-type "performance_degradation" --include-metrics true --severity-threshold "info"
```

**输入数据**：
```json
{
  "session_id": "db-performance-001",
  "target": "system",
  "fault_source": "db-cluster-01",
  "fault_type": "performance_degradation",
  "parameters": {
    "timeout": 600,
    "include_metrics": true,
    "severity_threshold": "info",
    "depth": 4
  },
  "metadata": {
    "context": {
      "performance_metrics": {
        "query_latency_increase": "300%",
        "connection_pool_usage": "95%"
      }
    }
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "db-performance-001",
  "execution_time": 120.5,
  "results": {
    "fault_analysis": {
      "source": {"id": "db-cluster-01", "type": "database", "status": "degraded"},
      "type": "performance_degradation",
      "root_cause_hypothesis": "连接池耗尽导致查询排队",
      "confidence": 0.90
    },
    "impact_assessment": {
      "affected_services": 12,
      "overall_severity": "warning",
      "impact_score": 60,
      "performance_impact": {
        "avg_response_time_increase": "45%",
        "throughput_reduction": "30%"
      }
    },
    "affected_components": [
      {
        "id": "order-service",
        "impact_severity": "high",
        "performance_metrics": {"response_time_p95": "2.5s", "error_rate": "5%"}
      },
      {
        "id": "payment-service",
        "impact_severity": "medium",
        "performance_metrics": {"response_time_p95": "1.8s", "error_rate": "2%"}
      }
    ],
    "recommendations": [
      {
        "priority": "immediate",
        "action": "扩容数据库连接池",
        "target": "db-cluster-01",
        "expected_benefit": "缓解查询排队问题"
      },
      {
        "priority": "short_term",
        "action": "优化高频查询的索引",
        "target": "db-cluster-01",
        "expected_benefit": "减少数据库负载"
      }
    ]
  },
  "metadata": {
    "skill_name": "fault-localization",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

## 注意事项

### 安全注意事项
- 需要读取服务配置和依赖关系的权限
- 依赖数据可能包含敏感信息（如内部服务地址）
- 可视化文件应存储在安全位置，及时清理
- 分析结果可能暴露系统架构细节，需控制访问权限
- 避免在生产环境进行可能影响系统的探测操作

### 性能注意事项
- 深度依赖分析可能消耗较多计算资源
- 建议根据系统规模调整`depth`参数（通常3-4层足够）
- 大规模系统分析可能需要较长时间（设置适当的`timeout`）
- 可视化生成会增加执行时间和存储需求
- 缓存依赖数据可以提高后续分析速度

### 环境要求
- 欧拉OS 2.0或更高版本
- 需要访问服务发现系统（如Consul、Eureka等）
- 需要监控系统接口（如Prometheus、Zabbix等）
- 需要配置管理系统访问权限
- 需要图形生成库（如Graphviz，用于可视化）

### 限制和约束
- 依赖数据的准确性和完整性直接影响分析结果
- 无法分析未知或未注册的服务依赖
- 动态服务发现可能遗漏瞬时依赖关系
- 故障传播模型基于预设规则，可能不覆盖所有场景
- 业务影响评估需要预定义的业务重要性映射

## 测试用例

### 测试1：正常流程测试
- **测试目的**：验证技能在标准故障场景下的完整流程
- **输入数据**：模拟web服务故障的标准输入
- **预期输出**：成功状态，包含完整的依赖分析和影响评估
- **验证点**：所有分析阶段都执行，输出格式正确，执行时间<60秒

### 测试2：深度依赖分析测试
- **测试目的**：验证技能在复杂依赖场景下的分析能力
- **输入数据**：设置`depth=5`，模拟多层依赖的系统
- **预期输出**：成功分析多层依赖关系，识别关键路径
- **验证点**：正确识别所有依赖层级，不出现循环分析

### 测试3：依赖数据缺失测试
- **测试目的**：验证技能在依赖数据不完整时的健壮性
- **输入数据**：模拟部分依赖数据不可用的情况
- **预期输出**：部分成功状态，清晰的缺失数据报告
- **验证点**：优雅降级，提供可行的替代方案建议

### 测试4：性能测试
- **测试目的**：验证技能在大规模系统下的性能表现
- **输入数据**：模拟包含100+服务的系统故障
- **预期输出**：在可接受时间内完成分析
- **验证点**：执行时间<300秒，内存使用在合理范围内

### 测试5：可视化生成测试
- **测试目的**：验证可视化功能的正确性
- **输入数据**：启用`visualization=true`
- **预期输出**：成功生成图表文件，文件格式正确
- **验证点**：图表文件可读，内容与分析结果一致

## 相关技能

### 前置技能
- **data-collector**：收集系统状态和服务信息
- **metric-analyzer**：分析性能指标，识别异常模式
- **log-analyzer**：分析日志，确定故障时间线和特征

### 后置技能
- **root-cause-analysis**：基于影响分析进行根因定位
- **controlled-repair**：根据优先级执行修复操作
- **intelligent-inspection**：监控修复后的系统状态

### 替代技能
- 无直接替代技能，但可与传统监控工具配合使用

### 补充技能
- **knowledge-base**：记录历史故障模式和影响分析
- **config-manager**：获取服务配置和依赖信息

## 更新日志

### 版本 1.0.0 (2026-02-03)
- 初始版本发布
- 实现基本的故障定位和影响分析
- 支持服务依赖图构建和分析
- 包含影响评估和优先级排序
- 支持可视化图表生成
- 完整的错误处理和恢复机制

### 版本 1.1.0 (计划中)
- 添加实时故障传播模拟
- 支持自定义影响评估规则
- 添加业务影响量化分析
- 支持多故障源同时分析
- 优化大规模系统分析性能
- 添加API接口用于集成调用

---

*故障定位是智能诊断系统的核心能力，准确的影响范围分析是有效故障处理的基础。*