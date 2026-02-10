# 影响范围识别示例

## 场景描述

本示例演示如何使用fault-localization技能识别系统故障的影响范围。场景基于一个分布式微服务架构的生产环境，其中一个关键服务出现故障，需要快速确定受影响的其他服务和组件，以便制定有效的应急响应和修复策略。

## 前置条件

### 系统环境
- 欧拉OS 2.0+运行环境
- 分布式微服务架构
- 服务注册与发现机制（如Consul、Eureka）
- 服务依赖关系数据可用

### 数据要求
- 服务拓扑和依赖关系数据
- 当前故障服务的标识信息
- 系统监控数据（可选，用于验证影响）

### 配置要求
- witty-diagnosis-agent已安装并配置
- fault-localization技能可用
- 访问服务注册中心的权限

## 执行步骤

### 步骤1：准备故障上下文

收集故障服务的相关信息：

```bash
# 获取故障服务基本信息
claude witty-diagnosis:data-collector \
  --data-sources services \
  --service-name order-service \
  --include-dependencies true \
  --output-format json \
  --output-file /tmp/fault-context-001.json

# 查看收集的服务信息
cat /tmp/fault-context-001.json | jq '.'
```

### 步骤2：执行影响范围分析

使用fault-localization技能分析影响范围：

```bash
claude witty-diagnosis:fault-localization \
  --session-id impact-analysis-001 \
  --fault-service order-service \
  --fault-type service_unavailable \
  --analysis-depth 3 \
  --include-indirect true \
  --propagation-model transitive_closure \
  --severity-threshold medium \
  --output-format detailed_json \
  --visualization-format graphviz
```

### 步骤3：提供分析输入

基于收集的服务数据，准备分析输入：

```json
{
  "session_id": "impact-analysis-001",
  "fault_context": {
    "service_name": "order-service",
    "fault_type": "service_unavailable",
    "detection_time": "2026-02-03T14:30:00Z",
    "severity": "high",
    "symptoms": [
      "HTTP 503 responses",
      "Connection timeouts",
      "Health check failures"
    ],
    "current_state": "complete_outage"
  },
  "system_topology": {
    "nodes": [
      {
        "id": "order-service",
        "type": "microservice",
        "role": "core_business",
        "criticality": "p0",
        "instance_count": 3,
        "current_status": "unhealthy",
        "health_score": 0.1
      },
      {
        "id": "user-service",
        "type": "microservice",
        "role": "supporting",
        "criticality": "p1",
        "instance_count": 2,
        "current_status": "healthy",
        "health_score": 0.9
      },
      {
        "id": "product-service",
        "type": "microservice",
        "role": "supporting",
        "criticality": "p1",
        "instance_count": 2,
        "current_status": "healthy",
        "health_score": 0.95
      },
      {
        "id": "payment-service",
        "type": "microservice",
        "role": "core_business",
        "criticality": "p0",
        "instance_count": 2,
        "current_status": "degraded",
        "health_score": 0.6
      },
      {
        "id": "inventory-service",
        "type": "microservice",
        "role": "supporting",
        "criticality": "p1",
        "instance_count": 2,
        "current_status": "healthy",
        "health_score": 0.85
      },
      {
        "id": "notification-service",
        "type": "microservice",
        "role": "non_critical",
        "criticality": "p2",
        "instance_count": 1,
        "current_status": "healthy",
        "health_score": 0.95
      },
      {
        "id": "api-gateway",
        "type": "infrastructure",
        "role": "traffic_routing",
        "criticality": "p0",
        "instance_count": 2,
        "current_status": "healthy",
        "health_score": 0.98
      },
      {
        "id": "redis-cache",
        "type": "infrastructure",
        "role": "caching",
        "criticality": "p1",
        "instance_count": 3,
        "current_status": "healthy",
        "health_score": 0.99
      },
      {
        "id": "postgres-db",
        "type": "infrastructure",
        "role": "data_persistence",
        "criticality": "p0",
        "instance_count": 1,
        "current_status": "healthy",
        "health_score": 0.97
      }
    ],
    "edges": [
      {
        "source": "api-gateway",
        "target": "order-service",
        "type": "http_request",
        "direction": "forward",
        "traffic_volume": "high",
        "critical": true
      },
      {
        "source": "order-service",
        "target": "user-service",
        "type": "rpc_call",
        "direction": "forward",
        "traffic_volume": "medium",
        "critical": true
      },
      {
        "source": "order-service",
        "target": "product-service",
        "type": "rpc_call",
        "direction": "forward",
        "traffic_volume": "high",
        "critical": true
      },
      {
        "source": "order-service",
        "target": "payment-service",
        "type": "rpc_call",
        "direction": "forward",
        "traffic_volume": "high",
        "critical": true
      },
      {
        "source": "order-service",
        "target": "inventory-service",
        "type": "rpc_call",
        "direction": "forward",
        "traffic_volume": "medium",
        "critical": true
      },
      {
        "source": "order-service",
        "target": "notification-service",
        "type": "async_message",
        "direction": "forward",
        "traffic_volume": "low",
        "critical": false
      },
      {
        "source": "order-service",
        "target": "redis-cache",
        "type": "cache_access",
        "direction": "bidirectional",
        "traffic_volume": "high",
        "critical": true
      },
      {
        "source": "order-service",
        "target": "postgres-db",
        "type": "database_query",
        "direction": "bidirectional",
        "traffic_volume": "high",
        "critical": true
      },
      {
        "source": "payment-service",
        "target": "user-service",
        "type": "rpc_call",
        "direction": "forward",
        "traffic_volume": "low",
        "critical": false
      },
      {
        "source": "payment-service",
        "target": "notification-service",
        "type": "async_message",
        "direction": "forward",
        "traffic_volume": "low",
        "critical": false
      }
    ],
    "metadata": {
      "total_services": 9,
      "total_dependencies": 10,
      "topology_version": "2.1.0",
      "timestamp": "2026-02-03T14:25:00Z"
    }
  },
  "analysis_parameters": {
    "max_depth": 3,
    "include_indirect_effects": true,
    "propagation_model": "transitive_closure",
    "severity_calculation": "weighted_criticality",
    "timeout_seconds": 30,
    "output_detail_level": "detailed"
  }
}
```

### 步骤4：验证分析结果

检查影响范围分析结果：

```bash
# 查看分析结果摘要
claude witty-diagnosis:fault-localization \
  --view-results impact-analysis-001 \
  --summary-only

# 导出影响范围可视化
claude witty-diagnosis:fault-localization \
  --export-impact-graph impact-analysis-001 \
  --format png \
  --output-file /tmp/impact-graph-001.png

# 获取受影响服务列表
claude witty-diagnosis:fault-localization \
  --get-affected-services impact-analysis-001 \
  --format csv
```

## 预期结果

### 分析结果示例

```json
{
  "status": "success",
  "session_id": "impact-analysis-001",
  "execution_time": 8.7,
  "analysis_results": {
    "fault_source": {
      "service": "order-service",
      "type": "microservice",
      "criticality": "p0",
      "status": "unhealthy"
    },
    "impact_scope": {
      "directly_affected": [
        {
          "service": "api-gateway",
          "impact_type": "upstream_dependency",
          "severity": "high",
          "reason": "直接调用order-service，无法处理订单相关请求",
          "estimated_impact": "订单相关API端点返回503错误"
        },
        {
          "service": "user-service",
          "impact_type": "downstream_dependency",
          "severity": "medium",
          "reason": "order-service依赖user-service获取用户信息",
          "estimated_impact": "用户信息查询可能失败或超时"
        },
        {
          "service": "product-service",
          "impact_type": "downstream_dependency",
          "severity": "high",
          "reason": "order-service依赖product-service验证产品库存",
          "estimated_impact": "无法验证产品可用性，订单创建受阻"
        },
        {
          "service": "payment-service",
          "impact_type": "downstream_dependency",
          "severity": "high",
          "reason": "order-service依赖payment-service处理支付",
          "estimated_impact": "支付流程中断，订单无法完成支付"
        },
        {
          "service": "inventory-service",
          "impact_type": "downstream_dependency",
          "severity": "medium",
          "reason": "order-service依赖inventory-service更新库存",
          "estimated_impact": "库存更新延迟，可能导致超卖"
        }
      ],
      "indirectly_affected": [
        {
          "service": "notification-service",
          "impact_type": "transitive_dependency",
          "severity": "low",
          "reason": "通过payment-service间接影响",
          "estimated_impact": "支付成功通知可能延迟"
        }
      ],
      "unaffected_services": ["redis-cache", "postgres-db"]
    },
    "propagation_analysis": {
      "propagation_depth": 2,
      "affected_service_count": 6,
      "unaffected_service_count": 3,
      "impact_coverage": "66.7%",
      "critical_paths": [
        {
          "path": ["api-gateway", "order-service", "payment-service"],
          "criticality": "p0_p0_p0",
          "is_critical": true,
          "bottleneck_services": ["order-service"]
        }
      ]
    },
    "severity_assessment": {
      "overall_severity": "high",
      "business_impact": {
        "affected_business_functions": ["order_processing", "payment_processing"],
        "estimated_revenue_impact": "high",
        "customer_impact": "significant"
      },
      "technical_impact": {
        "service_availability": "66.7% services affected",
        "data_consistency": "potential issues",
        "performance_degradation": "expected"
      }
    },
    "visualization_data": {
      "graph_nodes": 9,
      "graph_edges": 10,
      "highlighted_nodes": 6,
      "graph_format": "graphviz",
      "graph_data": "digraph ImpactScope { ... }"
    },
    "recommendations": {
      "immediate_actions": [
        {
          "action": "隔离order-service故障",
          "priority": "critical",
          "implementation": "更新api-gateway路由规则，将订单流量切换到备用区域",
          "expected_effect": "减少对上游服务的影响"
        },
        {
          "action": "启用降级策略",
          "priority": "high",
          "implementation": "为user-service、product-service等依赖服务配置降级逻辑",
          "expected_effect": "降低级联故障风险"
        }
      ],
      "communication_plan": [
        {
          "stakeholders": "customer_support",
          "message": "订单处理服务暂时不可用，正在紧急修复",
          "channels": ["internal_dashboard", "status_page"]
        },
        {
          "stakeholders": "development_teams",
          "message": "order-service故障影响范围分析完成，详细信息已共享",
          "channels": ["slack", "incident_channel"]
        }
      ],
      "monitoring_suggestions": [
        {
          "metric": "affected_services_health",
          "threshold": "any service health < 0.7",
          "alert": "warning",
          "action": "通知故障定位团队"
        }
      ]
    }
  },
  "metadata": {
    "skill_name": "fault-localization",
    "skill_version": "1.0.0",
    "analysis_timestamp": "2026-02-03T14:35:00Z",
    "topology_source": "service_registry_v2.1.0",
    "confidence_score": 0.89
  }
}
```

### 关键发现总结

基于影响范围分析，可以得出以下结论：

1. **核心影响**: 6个服务直接或间接受到影响，占系统服务的66.7%
2. **业务影响**: 订单处理和支付流程完全中断
3. **关键路径**: api-gateway → order-service → payment-service是关键路径
4. **隔离点**: api-gateway是有效的故障隔离点
5. **降级机会**: user-service和inventory-service有降级可能性

## 故障排除

### 常见问题

#### 拓扑数据不完整
**症状**: 分析结果不准确或遗漏依赖关系
**解决方法**:
1. 更新服务注册中心数据
2. 手动补充缺失的依赖关系
3. 使用`--allow-partial-topology`参数

#### 分析时间过长
**症状**: 大型系统拓扑分析超时
**解决方法**:
1. 减少分析深度（`--analysis-depth`）
2. 排除非关键服务
3. 使用缓存的分析结果

#### 影响范围过大
**症状**: 分析显示几乎所有服务都受影响
**解决方法**:
1. 调整传播模型参数
2. 提高严重性阈值
3. 验证拓扑数据的准确性

### 调试技巧

1. **分步分析**: 先分析直接依赖，再逐步扩展
2. **结果验证**: 与实际监控数据对比验证
3. **参数调整**: 尝试不同的传播模型和参数
4. **可视化检查**: 使用图形化输出验证分析结果

## 最佳实践

### 事前准备
1. **维护准确拓扑**: 定期更新服务依赖关系数据
2. **定义服务关键性**: 明确每个服务的关键性等级
3. **建立基线**: 记录正常时期的依赖关系模式

### 事中响应
1. **快速分析**: 故障发生后立即执行影响范围分析
2. **优先处理**: 根据分析结果优先处理高影响服务
3. **动态调整**: 根据实际情况调整分析参数

### 事后改进
1. **验证分析**: 事后验证分析结果的准确性
2. **更新知识**: 将验证的经验更新到知识库
3. **优化拓扑**: 根据分析结果优化系统架构

## 进阶用法

### 实时影响监控
```bash
# 持续监控服务健康并实时分析影响
claude witty-diagnosis:fault-localization \
  --monitor-mode active \
  --monitor-interval 30 \
  --services-to-monitor order-service,payment-service,user-service \
  --alert-threshold 0.7 \
  --output-stream websocket
```

### 假设分析
```bash
# 分析假设性故障的影响
claude witty-diagnosis:fault-localization \
  --what-if-scenario \
  --fault-service payment-service \
  --fault-type partial_outage \
  --availability 0.3 \
  --analysis-depth 4 \
  --output-file /tmp/what-if-analysis.json
```

### 架构优化建议
```bash
# 基于影响分析生成架构优化建议
claude witty-diagnosis:fault-localization \
  --generate-recommendations \
  --topology-file /tmp/system-topology.json \
  --optimization-goals reduce_impact improve_resilience \
  --output-format markdown
```

---

*示例版本：1.0.0*
*最后更新：2026-02-03*