---
name: trace-analyzer
description: 分布式链路追踪分析技能，负责服务调用链路重建、性能瓶颈分析、依赖关系可视化和根因定位
version: 1.0.0
category: analysis
author: witty-diagnosis-team
created: 2026-02-03
updated: 2026-02-03
tags:
  - tracing
  - performance-analysis
  - distributed-systems
  - bottleneck-detection
  - dependency-analysis
  - root-cause-localization
  - euler-os
  - diagnostics
---

# 链路追踪分析器 - 分布式链路追踪分析技能

## 概述

链路追踪分析器技能是witty-diagnosis-agent项目的关键分析组件，专门设计用于分析和诊断分布式系统中的服务调用链路问题。本技能通过分析追踪数据，重建完整的服务调用链路，识别性能瓶颈，可视化依赖关系，并定位问题根因，为分布式系统的性能优化和故障诊断提供深度洞察。

主要功能包括：
1. **调用链路重建**：从原始追踪数据重建完整的服务调用链路
2. **性能瓶颈分析**：分析链路中各节点的响应时间，识别性能瓶颈
3. **依赖关系可视化**：生成服务依赖关系图，展示系统拓扑结构
4. **根因定位**：在调用链路中定位问题根因节点
5. **拓扑分析**：分析系统拓扑结构，识别关键路径和单点故障
6. **异常检测**：检测链路中的异常模式，如超时、错误、重试等

本技能是分析支撑层的核心组件，为fault-localization、root-cause-analysis等核心诊断技能提供深度分析结果。

## 使用时机

### 应该使用此技能的情况：
- 分布式系统出现性能下降或响应延迟时
- 需要分析服务间调用关系和依赖时
- 定位微服务架构中的性能瓶颈时
- 分析复杂故障在调用链路中的传播路径时
- 进行系统容量规划和性能优化时
- 验证服务部署和配置变更的影响时
- 与其他诊断技能配合进行深度分析时

### 不应该使用此技能的情况：
- 只有单一服务日志，没有完整的调用链路数据时
- 需要实时监控而非事后分析时
- 仅需要基础指标分析时（使用metric-analyzer技能）
- 仅需要日志分析时（使用log-analyzer技能）
- 追踪数据不完整或格式不符合要求时

## 输入要求

### 必需输入

| 参数名 | 类型 | 描述 | 示例值 |
|--------|------|------|--------|
| `session_id` | string | 诊断会话ID | `"trace-analysis-001"` |
| `trace_data` | object/array | 追踪数据，支持多种格式 | 见输入格式示例 |
| `analysis_type` | string | 分析类型 | `"latency"`, `"dependency"`, `"root-cause"`, `"topology"`, `"comprehensive"` |

### 可选输入

| 参数名 | 类型 | 默认值 | 描述 |
|--------|------|--------|------|
| `timeout` | number | `300` | 执行超时时间（秒） |
| `verbosity` | string | `"info"` | 日志详细程度：`"debug"`, `"info"`, `"warn"`, `"error"` |
| `trace_format` | string | `"auto"` | 追踪数据格式：`"auto"`, `"jaeger"`, `"zipkin"`, `"skywalking"`, `"opentelemetry"` |
| `time_window` | object | `{"start": null, "end": null}` | 分析时间窗口，null表示自动检测 |
| `latency_threshold_ms` | number | `1000` | 延迟阈值（毫秒），超过此值视为异常 |
| `error_threshold_percent` | number | `5` | 错误率阈值（百分比），超过此值视为异常 |
| `dependency_depth` | number | `10` | 依赖分析深度，限制递归层级 |
| `visualization_format` | string | `"mermaid"` | 可视化格式：`"mermaid"`, `"dot"`, `"json"` |
| `output_format` | string | `"json"` | 输出格式：`"json"`, `"yaml"`, `"html"` |
| `include_raw_trace` | boolean | `false` | 是否在输出中包含原始追踪数据 |

### 输入格式示例

```json
{
  "session_id": "trace-analysis-session-001",
  "trace_data": [
    {
      "traceId": "abc123def456",
      "spanId": "span-001",
      "parentSpanId": null,
      "operationName": "HTTP GET /api/users",
      "startTime": "2026-02-03T17:30:00.123Z",
      "duration": 1250,
      "tags": {
        "http.method": "GET",
        "http.status_code": 200,
        "component": "nginx",
        "service.name": "gateway-service"
      },
      "logs": [
        {
          "timestamp": "2026-02-03T17:30:00.500Z",
          "fields": {
            "event": "request_started",
            "user_id": "user-123"
          }
        }
      ]
    },
    {
      "traceId": "abc123def456",
      "spanId": "span-002",
      "parentSpanId": "span-001",
      "operationName": "DB Query users",
      "startTime": "2026-02-03T17:30:00.250Z",
      "duration": 850,
      "tags": {
        "db.system": "postgresql",
        "db.statement": "SELECT * FROM users",
        "service.name": "user-service",
        "peer.service": "postgres-db"
      }
    }
  ],
  "analysis_type": "comprehensive",
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    "trace_format": "auto",
    "latency_threshold_ms": 1000,
    "error_threshold_percent": 5,
    "dependency_depth": 10,
    "visualization_format": "mermaid",
    "output_format": "json",
    "include_raw_trace": false
  },
  "metadata": {
    "request_id": "req-trace-001",
    "timestamp": "2026-02-03T17:30:00Z",
    "environment": "production",
    "issue_description": "API响应时间从200ms增加到1200ms",
    "affected_services": ["gateway-service", "user-service", "auth-service"]
  }
}
```

## 执行步骤

### 1. 初始化阶段
- **参数验证**：验证输入参数的有效性和完整性
- **数据格式检测**：自动检测或根据指定格式解析追踪数据
- **数据完整性检查**：检查追踪数据的完整性，识别缺失的span
- **环境准备**：初始化分析引擎，准备临时工作空间
- **资源评估**：评估数据规模，分配适当的内存和计算资源

### 2. 数据预处理阶段
- **数据清洗**：去除无效、重复或格式错误的追踪数据
- **时间对齐**：统一时间戳格式，处理时区差异
- **span关联**：根据traceId和parentSpanId重建span关系
- **数据增强**：补充缺失的元数据，标准化标签和日志格式
- **异常检测**：初步检测明显的异常模式（如负时长、时间倒序）

### 3. 调用链路重建阶段
- **链路构建**：根据span关系构建完整的调用树
- **根span识别**：识别每个trace的根span（parentSpanId为null）
- **链路完整性评估**：评估链路的完整性，识别缺失的中间span
- **服务映射**：建立服务名称到span集合的映射关系
- **调用路径提取**：提取所有可能的调用路径

### 4. 性能分析阶段
- **延迟计算**：计算每个span和整个链路的延迟
- **瓶颈识别**：识别延迟最高的节点和关键路径
- **百分位分析**：计算P50、P90、P95、P99延迟
- **吞吐量分析**：分析单位时间内的请求处理量
- **资源使用关联**：将延迟与资源使用指标关联分析

### 5. 依赖关系分析阶段
- **服务依赖提取**：从调用链路中提取服务间依赖关系
- **依赖强度计算**：基于调用频率和延迟计算依赖强度
- **循环依赖检测**：检测服务间的循环依赖
- **关键路径分析**：识别系统中的关键调用路径
- **单点故障识别**：识别可能成为单点故障的服务

### 6. 根因定位阶段
- **异常模式识别**：识别延迟异常、错误率异常等模式
- **影响传播分析**：分析问题在调用链路中的传播路径
- **相关性分析**：分析不同服务异常之间的相关性
- **根因候选生成**：生成可能的根因节点列表
- **置信度评估**：为每个根因候选评估置信度

### 7. 可视化生成阶段
- **拓扑图生成**：生成服务依赖拓扑图
- **调用链路图生成**：生成具体的调用链路图
- **时序图生成**：生成带时间轴的调用时序图
- **热力图生成**：生成延迟热力图
- **报告整合**：将分析结果整合为综合报告

### 8. 结果生成阶段
- **结果组装**：将各阶段分析结果组装为统一结构
- **摘要生成**：生成执行摘要和关键发现
- **建议生成**：基于分析结果生成优化建议
- **资源清理**：清理临时文件和中间数据
- **输出生成**：按指定格式生成最终输出

## 输出格式

### 成功输出格式

```json
{
  "status": "success",
  "session_id": "trace-analysis-session-001",
  "execution_time": 28.5,
  "results": {
    "summary": {
      "total_traces": 1250,
      "total_spans": 8920,
      "unique_services": 15,
      "analysis_time_window": {
        "start": "2026-02-03T17:00:00Z",
        "end": "2026-02-03T18:00:00Z"
      },
      "data_quality": {
        "completeness_score": 0.92,
        "consistency_score": 0.88,
        "accuracy_score": 0.95
      }
    },
    "performance_analysis": {
      "overall_latency": {
        "avg_ms": 245.6,
        "p50_ms": 185.2,
        "p90_ms": 420.8,
        "p95_ms": 580.3,
        "p99_ms": 1250.5,
        "max_ms": 1850.7
      },
      "bottlenecks": [
        {
          "service_name": "user-service",
          "operation_name": "DB Query users",
          "avg_latency_ms": 850.3,
          "contribution_percent": 34.6,
          "call_count": 1250,
          "suggestions": [
            "优化数据库查询索引",
            "考虑添加查询缓存",
            "检查数据库连接池配置"
          ]
        },
        {
          "service_name": "auth-service",
          "operation_name": "JWT Token Validation",
          "avg_latency_ms": 320.5,
          "contribution_percent": 13.1,
          "call_count": 1250,
          "suggestions": [
            "优化JWT验证算法",
            "考虑使用本地缓存验证结果",
            "检查密钥存储性能"
          ]
        }
      ],
      "critical_paths": [
        {
          "path": ["gateway-service", "auth-service", "user-service", "postgres-db"],
          "avg_latency_ms": 1250.8,
          "frequency": 1250,
          "contribution_percent": 51.2
        }
      ]
    },
    "dependency_analysis": {
      "service_dependencies": [
        {
          "source": "gateway-service",
          "target": "auth-service",
          "call_count": 1250,
          "avg_latency_ms": 45.2,
          "error_rate_percent": 0.8,
          "dependency_strength": 0.95
        },
        {
          "source": "auth-service",
          "target": "user-service",
          "call_count": 1250,
          "avg_latency_ms": 320.5,
          "error_rate_percent": 2.1,
          "dependency_strength": 0.92
        },
        {
          "source": "user-service",
          "target": "postgres-db",
          "call_count": 1250,
          "avg_latency_ms": 850.3,
          "error_rate_percent": 1.5,
          "dependency_strength": 0.98
        }
      ],
      "circular_dependencies": [],
      "single_points_of_failure": [
        {
          "service_name": "postgres-db",
          "dependent_services": ["user-service", "order-service", "inventory-service"],
          "criticality_score": 0.95
        }
      ]
    },
    "root_cause_analysis": {
      "primary_root_cause": {
        "service_name": "user-service",
        "operation_name": "DB Query users",
        "confidence_score": 0.88,
        "evidence": [
          "延迟贡献度最高（34.6%）",
          "错误率相对较高（1.5%）",
          "位于关键路径上",
          "下游依赖postgres-db也存在延迟"
        ],
        "impact_scope": ["gateway-service", "auth-service", "user-service", "postgres-db"]
      },
      "secondary_root_causes": [
        {
          "service_name": "auth-service",
          "operation_name": "JWT Token Validation",
          "confidence_score": 0.72,
          "evidence": [
            "延迟贡献度第二高（13.1%）",
            "位于关键路径起始位置"
          ]
        }
      ],
      "propagation_path": ["user-service → auth-service → gateway-service"]
    },
    "visualizations": {
      "topology_diagram": "graph TD\n  A[gateway-service] --> B[auth-service]\n  B --> C[user-service]\n  C --> D[postgres-db]\n  A --> E[order-service]\n  E --> D\n  A --> F[inventory-service]\n  F --> D",
      "critical_path_timeline": "timeline\n  title 关键路径时间线\n  section gateway-service\n    HTTP GET /api/users : 2026-02-03T17:30:00.123Z, 45ms\n  section auth-service\n    JWT Token Validation : 2026-02-03T17:30:00.168Z, 320ms\n  section user-service\n    DB Query users : 2026-02-03T17:30:00.488Z, 850ms\n  section postgres-db\n    SQL Execution : 2026-02-03T17:30:00.538Z, 800ms",
      "latency_heatmap": {
        "data": [
          {"service": "gateway-service", "operation": "HTTP GET /api/users", "latency_ms": 45.2},
          {"service": "auth-service", "operation": "JWT Token Validation", "latency_ms": 320.5},
          {"service": "user-service", "operation": "DB Query users", "latency_ms": 850.3}
        ],
        "threshold_ms": 1000
      }
    },
    "recommendations": {
      "high_priority": [
        {
          "action": "优化user-service的数据库查询",
          "impact": "预计减少总延迟34.6%",
          "effort": "中等",
          "details": "检查查询计划，添加适当索引，考虑查询缓存"
        },
        {
          "action": "评估postgres-db性能",
          "impact": "可能解决根本性能问题",
          "effort": "高",
          "details": "检查数据库配置、硬件资源、连接池设置"
        }
      ],
      "medium_priority": [
        {
          "action": "优化auth-service的JWT验证",
          "impact": "预计减少总延迟13.1%",
          "effort": "低",
          "details": "考虑缓存验证结果，优化密钥存储访问"
        }
      ],
      "long_term": [
        {
          "action": "引入数据库读写分离",
          "impact": "分散数据库负载，提高系统吞吐量",
          "effort": "高",
          "details": "将读操作路由到只读副本，写操作到主库"
        },
        {
          "action": "实施服务降级和熔断机制",
          "impact": "提高系统韧性，防止级联故障",
          "effort": "中等",
          "details": "为关键依赖服务配置熔断器，实现优雅降级"
        }
      ]
    }
  },
  "metadata": {
    "skill_name": "trace-analyzer",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:28Z",
    "execution_mode": "comprehensive",
    "analysis_types": ["performance", "dependency", "root_cause", "visualization"],
    "data_format_version": "1.0.0"
  }
}
```

### 部分成功输出格式

```json
{
  "status": "partial",
  "session_id": "trace-analysis-session-001",
  "execution_time": 22.3,
  "results": {
    "summary": {
      "total_traces": 1250,
      "total_spans": 8920,
      "unique_services": 15,
      "data_quality": {
        "completeness_score": 0.65,
        "consistency_score": 0.72,
        "accuracy_score": 0.88
      },
      "warnings": [
        "追踪数据不完整，部分span缺失parent信息",
        "时间戳格式不一致，可能影响时序分析精度"
      ]
    },
    "performance_analysis": {
      // 可用的性能分析结果
    },
    "partial_results": {
      "successful_analyses": ["performance_analysis", "dependency_analysis"],
      "failed_analyses": ["root_cause_analysis"],
      "failure_reasons": {
        "root_cause_analysis": "数据不完整，无法进行可靠的根因定位"
      }
    }
  },
  "metadata": {
    "skill_name": "trace-analyzer",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:22Z"
  }
}
```

### 错误输出格式

```json
{
  "status": "error",
  "session_id": "trace-analysis-session-001",
  "execution_time": 5.2,
  "error_code": "INVALID_TRACE_DATA",
  "error_message": "追踪数据格式无效或无法解析",
  "details": {
    "failed_step": "数据预处理阶段",
    "failed_module": "数据格式检测",
    "error_context": {
      "trace_format": "auto",
      "data_sample": "{\"invalid\": \"format\"}",
      "expected_formats": ["jaeger", "zipkin", "skywalking", "opentelemetry"]
    }
  },
  "suggestions": [
    "检查追踪数据格式是否符合支持的规范",
    "明确指定trace_format参数",
    "提供数据样本进行格式验证",
    "参考示例输入格式调整数据"
  ],
  "metadata": {
    "skill_name": "trace-analyzer",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:05Z"
  }
}
```

### 输出字段说明

| 字段名 | 类型 | 必需 | 描述 |
|--------|------|------|------|
| `status` | string | 是 | 执行状态：`"success"`, `"partial"`, `"error"` |
| `session_id` | string | 是 | 诊断会话ID |
| `execution_time` | number | 是 | 执行时间（秒） |
| `results.summary` | object | 是 | 分析结果摘要信息 |
| `results.performance_analysis` | object | 是 | 性能分析结果 |
| `results.dependency_analysis` | object | 是 | 依赖关系分析结果 |
| `results.root_cause_analysis` | object | 否 | 根因分析结果（分析类型包含时） |
| `results.visualizations` | object | 否 | 可视化结果（请求时生成） |
| `results.recommendations` | object | 否 | 优化建议（分析成功时生成） |
| `results.partial_results` | object | 否 | 部分成功时的详细信息 |
| `metadata` | object | 是 | 元数据信息 |
| `error_code` | string | 否 | 错误代码（仅错误时） |
| `error_message` | string | 否 | 错误描述（仅错误时） |
| `details` | object | 否 | 详细错误信息（仅错误时） |
| `suggestions` | array | 否 | 修复建议（仅错误时） |

## 示例

### 示例1：性能瓶颈分析

**场景描述**：
用户报告API响应时间显著增加，需要分析性能瓶颈所在。

**命令调用**：
```bash
claude witty-diagnosis:trace-analyzer --analysis-type latency --trace-data trace.json --latency-threshold-ms 500
```

**输入数据**：
```json
{
  "session_id": "performance-bottleneck-001",
  "trace_data": [
    // 实际追踪数据（此处省略详细数据）
  ],
  "analysis_type": "latency",
  "parameters": {
    "timeout": 300,
    "latency_threshold_ms": 500,
    "output_format": "json"
  },
  "metadata": {
    "request_id": "req-perf-001",
    "issue_description": "用户查询API响应时间从200ms增加到800ms",
    "time_range": "2026-02-03T17:00:00Z 到 2026-02-03T18:00:00Z"
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "performance-bottleneck-001",
  "execution_time": 15.8,
  "results": {
    "summary": {
      "total_traces": 850,
      "total_spans": 4250,
      "unique_services": 8,
      "analysis_time_window": {
        "start": "2026-02-03T17:00:00Z",
        "end": "2026-02-03T18:00:00Z"
      }
    },
    "performance_analysis": {
      "overall_latency": {
        "avg_ms": 785.3,
        "p50_ms": 620.5,
        "p90_ms": 1250.8,
        "p95_ms": 1580.2,
        "p99_ms": 2100.5
      },
      "bottlenecks": [
        {
          "service_name": "product-service",
          "operation_name": "Elasticsearch Query",
          "avg_latency_ms": 520.8,
          "contribution_percent": 66.3,
          "call_count": 850,
          "exceeds_threshold": true,
          "threshold_ms": 500
        }
      ],
      "critical_paths": [
        {
          "path": ["gateway-service", "product-service", "elasticsearch"],
          "avg_latency_ms": 785.3,
          "frequency": 850
        }
      ]
    },
    "recommendations": {
      "high_priority": [
        {
          "action": "优化product-service的Elasticsearch查询",
          "impact": "预计减少总延迟66.3%",
          "details": "检查查询DSL，优化索引设计，考虑查询缓存"
        }
      ]
    }
  },
  "metadata": {
    "skill_name": "trace-analyzer",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

### 示例2：依赖关系分析

**场景描述**：
计划进行系统架构重构，需要了解当前服务间的依赖关系。

**命令调用**：
```bash
claude witty-diagnosis:trace-analyzer --analysis-type dependency --trace-data trace.json --visualization-format mermaid --dependency-depth 5
```

**输入数据**：
```json
{
  "session_id": "dependency-analysis-001",
  "trace_data": [
    // 实际追踪数据（此处省略详细数据）
  ],
  "analysis_type": "dependency",
  "parameters": {
    "dependency_depth": 5,
    "visualization_format": "mermaid",
    "output_format": "json"
  },
  "metadata": {
    "request_id": "req-arch-001",
    "purpose": "架构重构规划",
    "scope": "所有微服务"
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "dependency-analysis-001",
  "execution_time": 18.2,
  "results": {
    "summary": {
      "total_traces": 1250,
      "total_spans": 8920,
      "unique_services": 15
    },
    "dependency_analysis": {
      "service_dependencies": [
        {
          "source": "gateway-service",
          "target": "auth-service",
          "call_count": 1250,
          "avg_latency_ms": 45.2,
          "dependency_strength": 0.95
        },
        {
          "source": "gateway-service",
          "target": "product-service",
          "call_count": 980,
          "avg_latency_ms": 320.5,
          "dependency_strength": 0.78
        },
        // 更多依赖关系...
      ],
      "circular_dependencies": [
        {
          "cycle": ["order-service", "inventory-service", "payment-service", "order-service"],
          "services_involved": 3,
          "call_count": 125
        }
      ],
      "single_points_of_failure": [
        {
          "service_name": "postgres-db",
          "dependent_services": ["user-service", "order-service", "inventory-service"],
          "criticality_score": 0.95
        }
      ]
    },
    "visualizations": {
      "topology_diagram": "graph TD\n  A[gateway-service] --> B[auth-service]\n  A --> C[product-service]\n  A --> D[order-service]\n  D --> E[inventory-service]\n  D --> F[payment-service]\n  F --> D\n  B --> G[user-service]\n  C --> H[elasticsearch]\n  G --> I[postgres-db]\n  D --> I\n  E --> I"
    },
    "recommendations": {
      "architectural": [
        {
          "action": "打破order-service和payment-service的循环依赖",
          "impact": "提高系统可维护性，减少级联故障风险",
          "details": "考虑引入消息队列或事件驱动架构"
        },
        {
          "action": "为postgres-db引入读写分离或分库分表",
          "impact": "分散数据库负载，提高系统可用性",
          "details": "评估数据访问模式，设计合适的数据分区策略"
        }
      ]
    }
  },
  "metadata": {
    "skill_name": "trace-analyzer",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

## 注意事项

### 安全注意事项
- **数据敏感性**：追踪数据可能包含敏感信息（如用户ID、查询参数），支持自动脱敏
- **访问控制**：确保只有授权用户能够访问追踪数据和分析结果
- **数据保留**：分析完成后自动清理临时数据，不持久化原始追踪数据
- **审计日志**：记录所有分析操作，支持安全审计和合规要求
- **输出控制**：支持配置输出内容的详细程度，避免泄露敏感信息

### 性能注意事项
- **数据规模**：大规模追踪数据（>100MB）可能需要更多内存和计算资源
- **分析深度**：深度依赖分析和复杂模式识别会增加计算复杂度
- **内存管理**：采用流式处理技术处理大规模数据，避免内存溢出
- **并发分析**：支持并行处理多个trace，提高分析效率
- **缓存策略**：对中间结果实施缓存，优化重复分析性能

### 环境要求
- **内存要求**：建议至少2GB可用内存，大规模分析需要4GB以上
- **CPU要求**：多核CPU可显著提高分析性能
- **存储空间**：需要临时存储空间，建议至少500MB可用空间
- **依赖库**：需要图形处理库支持可视化生成
- **网络条件**：如果追踪数据来自远程源，需要稳定的网络连接

### 限制和约束
- **数据完整性**：分析结果质量依赖于追踪数据的完整性
- **时间精度**：时间戳精度影响延迟分析的准确性
- **格式支持**：支持主流追踪格式，自定义格式可能需要适配
- **实时性**：非实时分析工具，适合事后分析和批量处理
- **服务发现**：需要追踪数据包含服务名称信息才能进行依赖分析

## 测试用例

### 测试1：完整链路分析测试
- **测试目的**：验证技能对完整追踪数据的全面分析能力
- **输入数据**：包含完整调用链路的标准化追踪数据
- **预期输出**：成功状态，包含所有分析维度的完整结果
- **验证点**：
  - 正确重建调用链路
  - 准确识别性能瓶颈
  - 生成正确的依赖关系图
  - 提供合理的根因定位
  - 执行时间在预期范围内（<30秒）

### 测试2：性能瓶颈识别测试
- **测试目的**：验证延迟分析和瓶颈识别功能
- **输入数据**：包含明显延迟异常的追踪数据
- **预期输出**：成功状态，准确识别延迟瓶颈
- **验证点**：
  - 正确计算各节点延迟
  - 准确识别超过阈值的瓶颈
  - 提供合理的优化建议
  - 延迟计算精度在可接受范围内

### 测试3：依赖关系分析测试
- **测试目的**：验证服务依赖关系提取和分析功能
- **输入数据**：包含复杂服务调用的追踪数据
- **预期输出**：成功状态，准确提取依赖关系
- **验证点**：
  - 正确识别服务间调用关系
  - 检测循环依赖
  - 识别单点故障
  - 生成正确的拓扑图

### 测试4：数据不完整测试
- **测试目的**：验证对不完整追踪数据的处理能力
- **输入数据**：缺失部分span或parent信息的追踪数据
- **预期输出**：部分成功状态，清晰的警告信息
- **验证点**：
  - 优雅处理数据不完整情况
  - 提供数据质量评估
  - 尽可能完成可用的分析
  - 明确的警告和建议

### 测试5：格式兼容性测试
- **测试目的**：验证对不同追踪格式的支持
- **输入数据**：不同格式（Jaeger、Zipkin、SkyWalking）的追踪数据
- **预期输出**：成功状态，正确解析和分析
- **验证点**：
  - 自动检测或正确指定格式
  - 统一解析为内部格式
  - 分析结果一致
  - 格式转换无数据丢失

## 相关技能

### 前置技能
- **data-collector**：收集系统运行数据，可能包含追踪数据
- **log-analyzer**：分析服务日志，为追踪分析提供补充信息
- **metric-analyzer**：分析性能指标，与追踪分析结果相互验证

### 后置技能
- **fault-localization**：基于追踪分析结果进行故障定位
- **root-cause-analysis**：使用追踪分析结果进行深度根因分析
- **controlled-repair**：基于分析结果执行针对性的修复操作
- **knowledge-base**：将分析结果存储到知识库，建立性能基线

### 替代技能
- 无直接替代技能，但可以与其他APM工具（如Jaeger、Zipkin）配合使用

### 补充技能
- **intelligent-inspection**：定期自动执行链路追踪分析
- **config-manager**：管理追踪采集和分析的配置
- **knowledge-base**：存储历史追踪模式和性能基线

## 更新日志

### 版本 1.0.0 (2026-02-03)
- 初始版本发布
- 实现完整的链路追踪分析功能：调用链路重建、性能瓶颈分析、依赖关系分析、根因定位
- 支持多种追踪数据格式：Jaeger、Zipkin、SkyWalking、OpenTelemetry
- 提供丰富的可视化输出：拓扑图、时序图、热力图
- 完整的错误处理和数据质量评估
- 符合项目数据格式规范
- 包含全面的测试用例

### 版本 1.1.0 (计划中)
- 添加实时流式分析支持
- 支持自定义分析规则和模式检测
- 增强机器学习辅助的根因定位
- 添加对比分析功能（与历史基线对比）
- 支持分布式追踪数据聚合分析

### 版本 1.2.0 (计划中)
- 添加预测性分析功能（趋势预测、容量规划）
- 支持跨多个时间段的趋势分析
- 增强可视化交互功能
- 添加API性能SLA分析
- 支持自定义指标计算和报警规则

---

*文档版本：1.0.0*
*最后更新：2026-02-03*