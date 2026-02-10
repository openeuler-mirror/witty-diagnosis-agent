# 根因查找示例

## 场景描述

数据库集群出现连接异常问题，多个应用报告数据库连接超时和查询失败。故障现象复杂，涉及网络、数据库、应用多个层面。需要系统性地查找根本原因，解决这一影响多个业务系统的关键问题。

## 前置条件

### 系统环境
- 数据库：MySQL集群（一主两从）
- 网络：千兆以太网，VLAN隔离
- 应用：多个微服务应用
- 监控系统：Prometheus + Grafana
- 日志系统：ELK Stack

### 数据准备
- 网络监控数据（丢包率、延迟、带宽）
- 数据库监控指标（连接数、查询性能、锁等待）
- 应用日志（连接错误、超时日志）
- 系统日志（内核日志、系统消息）
- 历史故障数据库记录

### 权限要求
- 跨系统数据访问权限
- 数据库诊断权限
- 网络设备访问权限
- 历史数据库查询权限

## 执行步骤

### 步骤1：准备综合故障数据
整合来自多个系统的故障数据：

```json
{
  "session_id": "db-cluster-rca-20260203-001",
  "target": "database",
  "fault_data": {
    "issues": [
      {
        "id": "db-conn-issue-001",
        "type": "database_connectivity",
        "severity": "critical",
        "description": "数据库集群连接异常，多个应用报告连接超时",
        "symptoms": [
          "connection_timeouts",
          "query_failures",
          "high_latency",
          "connection_resets",
          "replication_lag"
        ],
        "possible_causes": [
          "network_partition",
          "database_overload",
          "firewall_rules",
          "dns_resolution",
          "resource_exhaustion",
          "replication_failure",
          "storage_issues"
        ],
        "evidence": {
          "network_metrics": {
            "packet_loss_master": "8.5%",
            "packet_loss_slave1": "12.3%",
            "packet_loss_slave2": "3.2%",
            "latency_master_ms": 245,
            "latency_slave1_ms": 320,
            "latency_slave2_ms": 85,
            "bandwidth_utilization": "65%"
          },
          "database_metrics": {
            "connections_total": 950,
            "connections_active": 920,
            "max_connections": 1000,
            "threads_running": 85,
            "threads_connected": 920,
            "query_response_time_p95": 1250,
            "lock_wait_time": 45.2,
            "replication_lag_seconds": 120
          },
          "system_metrics": {
            "cpu_usage_master": "75%",
            "memory_usage_master": "82%",
            "disk_iowait_master": "35%",
            "swap_usage_master": "45%"
          },
          "logs": [
            {
              "timestamp": "2026-02-03T16:45:00Z",
              "level": "ERROR",
              "message": "MySQL connection timeout after 30 seconds",
              "source": "app-01",
              "component": "database_connector"
            },
            {
              "timestamp": "2026-02-03T16:50:00Z",
              "level": "ERROR",
              "message": "Got timeout reading communication packets",
              "source": "mysql-master",
              "component": "mysqld"
            },
            {
              "timestamp": "2026-02-03T16:55:00Z",
              "level": "WARNING",
              "message": "Network interface eth0: dropped packets increasing",
              "source": "master-server",
              "component": "kernel"
            },
            {
              "timestamp": "2026-02-03T17:00:00Z",
              "level": "ERROR",
              "message": "Replication I/O thread: error reconnecting to master",
              "source": "mysql-slave1",
              "component": "mysqld"
            }
          ],
          "events": [
            {
              "timestamp": "2026-02-03T16:30:00Z",
              "type": "network_maintenance",
              "description": "Network switch firmware update started",
              "impact": "possible_network_disruption"
            },
            {
              "timestamp": "2026-02-03T16:40:00Z",
              "type": "application_deployment",
              "description": "New batch job deployed to process queue",
              "impact": "increased_database_load"
            }
          ]
        },
        "impact_assessment": {
          "affected_applications": ["app-01", "app-02", "app-03", "batch-processor"],
          "affected_users": 5000,
          "business_services": ["checkout", "inventory", "reporting"],
          "severity_level": "P1",
          "recovery_time_objective": "1小时"
        },
        "temporal_pattern": {
          "onset_time": "2026-02-03T16:45:00Z",
          "escalation_time": "2026-02-03T16:55:00Z",
          "peak_time": "2026-02-03T17:05:00Z",
          "current_state": "ongoing",
          "pattern_type": "gradual_degradation"
        }
      }
    ],
    "system_topology": {
      "database_cluster": {
        "master": {
          "hostname": "db-master-01",
          "role": "primary",
          "location": "rack-a",
          "network_segment": "vlan-100"
        },
        "slaves": [
          {
            "hostname": "db-slave-01",
            "role": "replica",
            "location": "rack-b",
            "network_segment": "vlan-100",
            "replication_status": "broken"
          },
          {
            "hostname": "db-slave-02",
            "role": "replica",
            "location": "rack-c",
            "network_segment": "vlan-200",
            "replication_status": "healthy"
          }
        ]
      },
      "network_infrastructure": {
        "core_switch": "switch-core-01",
        "access_switches": ["switch-rack-a", "switch-rack-b", "switch-rack-c"],
        "firewall": "fw-dmz-01",
        "load_balancer": "lb-db-01"
      },
      "application_servers": [
        {
          "name": "app-01",
          "type": "web_server",
          "database_connections": 150,
          "location": "rack-d"
        },
        {
          "name": "batch-processor",
          "type": "batch_job",
          "database_connections": 300,
          "location": "rack-e"
        }
      ]
    },
    "context": {
      "environment": "production",
      "business_period": "peak_traffic",
      "recent_changes": [
        {
          "time": "2026-02-03T16:30:00Z",
          "type": "network_change",
          "description": "Core switch firmware update",
          "change_id": "NET-20260203-001"
        },
        {
          "time": "2026-02-03T16:40:00Z",
          "type": "application_change",
          "description": "Deployed new batch processing job",
          "change_id": "APP-20260203-001"
        }
      ],
      "constraints": {
        "maintenance_window": "none",
        "rollback_possible": "partial",
        "external_dependencies": ["payment_gateway", "inventory_system"]
      }
    }
  },
  "parameters": {
    "timeout": 600,
    "verbosity": "debug",
    "analysis_algorithms": ["causal_graph", "bayesian", "historical_matching", "temporal_analysis"],
    "confidence_threshold": 0.65,
    "use_historical_data": true,
    "max_hypotheses": 7,
    "include_explanations": true,
    "cross_system_analysis": true,
    "output_format": "json"
  },
  "metadata": {
    "request_id": "req-db-cluster-001",
    "timestamp": "2026-02-03T17:10:00Z",
    "environment": "production",
    "priority": "critical",
    "business_impact": "multiple_critical_services_affected",
    "requester": "database_team",
    "escalation_level": "L2",
    "tags": ["database", "network", "cluster", "critical"]
  }
}
```

### 步骤2：执行跨系统根因分析
执行包含跨系统分析的根因查找：

```bash
claude witty-diagnosis:root-cause-analysis \
  --session-id "db-cluster-rca-20260203-001" \
  --target database \
  --analysis-algorithms causal-graph bayesian historical-matching temporal-analysis \
  --confidence-threshold 0.65 \
  --use-historical-data \
  --cross-system-analysis \
  --max-hypotheses 7 \
  --timeout 600 \
  --verbosity debug \
  --input-file /tmp/db-cluster-fault-data.json
```

### 步骤3：监控多维度分析过程
监控复杂的分析过程：

```bash
# 查看详细分析日志
tail -f /var/log/witty-diagnosis/root-cause-analysis-debug.log | grep -E "(causal_graph|bayesian|temporal)"

# 检查各算法进度
claude witty-diagnosis:progress --session-id "db-cluster-rca-20260203-001"

# 监控资源使用
claude witty-diagnosis:monitor --skill root-cause-analysis --session-id "db-cluster-rca-20260203-001"
```

### 步骤4：分析复杂输出结果
分析包含多个系统维度的根因分析结果：

## 预期结果

### 成功输出示例
```json
{
  "status": "success",
  "session_id": "db-cluster-rca-20260203-001",
  "execution_time": 125.8,
  "results": {
    "summary": {
      "total_issues": 1,
      "analyzed_issues": 1,
      "root_causes_found": 1,
      "highest_confidence": 0.88,
      "analysis_algorithms_used": ["causal_graph", "bayesian", "historical_matching", "temporal_analysis"],
      "historical_patterns_matched": 2,
      "cross_system_analysis": true,
      "analysis_complexity": "very_high"
    },
    "root_cause_analysis": {
      "primary_root_cause": {
        "id": "rc-db-cluster-001",
        "type": "network_partition",
        "description": "核心交换机固件更新导致网络分区，影响数据库主从复制和应用连接",
        "confidence": 0.88,
        "evidence": [
          {
            "type": "temporal_correlation",
            "description": "故障开始时间与网络维护开始时间完全一致",
            "weight": 0.95,
            "details": "故障于16:45开始，网络维护于16:30开始，15分钟后出现症状"
          },
          {
            "type": "network_metrics",
            "description": "主库和从库1之间高丢包率（8.5%-12.3%）",
            "weight": 0.90,
            "details": "异常的网络丢包模式，从库2正常（3.2%）"
          },
          {
            "type": "topological_analysis",
            "description": "故障模式与网络拓扑结构匹配",
            "weight": 0.88,
            "details": "同一VLAN内的服务器受影响，跨VLAN的从库2正常"
          },
          {
            "type": "log_correlation",
            "description": "网络丢包日志与数据库连接错误时间匹配",
            "weight": 0.85,
            "details": "内核丢包日志出现后立即出现数据库连接错误"
          },
          {
            "type": "historical_pattern",
            "description": "匹配历史网络维护导致的数据库故障模式",
            "weight": 0.82,
            "details": "历史数据库中有2个类似案例"
          },
          {
            "type": "causal_isolation",
            "description": "数据库资源使用正常，排除数据库自身问题",
            "weight": 0.80,
            "details": "CPU、内存、磁盘使用率均在正常范围内"
          }
        ],
        "causal_chain": [
          {
            "step": 1,
            "cause": "核心交换机固件更新",
            "effect": "网络包处理异常，增加丢包率",
            "confidence": 0.92,
            "time_offset_minutes": 0,
            "system": "network"
          },
          {
            "step": 2,
            "cause": "网络丢包率增加",
            "effect": "数据库主从复制数据包丢失",
            "confidence": 0.90,
            "time_offset_minutes": 5,
            "system": "network"
          },
          {
            "step": 3,
            "cause": "复制数据包丢失",
            "effect": "从库1复制线程断开",
            "confidence": 0.88,
            "time_offset_minutes": 10,
            "system": "database"
          },
          {
            "step": 4,
            "cause": "从库复制失败",
            "effect": "负载均衡器将流量重定向到主库",
            "confidence": 0.85,
            "time_offset_minutes": 12,
            "system": "infrastructure"
          },
          {
            "step": 5,
            "cause": "主库连接数激增",
            "effect": "连接池接近耗尽",
            "confidence": 0.83,
            "time_offset_minutes": 15,
            "system": "database"
          },
          {
            "step": 6,
            "cause": "连接池紧张",
            "effect": "新连接建立超时",
            "confidence": 0.80,
            "time_offset_minutes": 18,
            "system": "application"
          },
          {
            "step": 7,
            "cause": "连接超时",
            "effect": "应用报告数据库连接失败",
            "confidence": 0.78,
            "time_offset_minutes": 20,
            "system": "business"
          }
        ],
        "explanations": [
          "因果图分析显示网络问题是所有症状的共同上游原因",
          "贝叶斯网络计算网络问题的后验概率为0.87，显著高于其他假设",
          "时间序列分析显示网络维护开始时间与故障开始时间高度相关",
          "历史模式匹配找到2个网络维护导致的类似数据库故障案例",
          "跨系统分析排除数据库资源问题和应用层问题",
          "网络拓扑分析确认故障范围与网络分段边界一致"
        ],
        "root_cause_context": {
          "root_cause_location": "核心交换机switch-core-01",
          "affected_components": ["db-master-01", "db-slave-01", "app-01", "batch-processor"],
          "unaffected_components": ["db-slave-02"],
          "failure_boundary": "VLAN-100",
          "propagation_path": "网络→数据库→应用→业务"
        }
      },
      "alternative_hypotheses": [
        {
          "id": "rc-db-cluster-002",
          "type": "database_overload",
          "description": "数据库过载导致连接池耗尽",
          "confidence": 0.42,
          "evidence": [
            {
              "type": "metric",
              "description": "数据库连接数接近最大值",
              "weight": 0.7
            }
          ],
          "assessment": "这是网络问题的次级效应，不是根本原因",
          "relationship_to_primary": "consequence"
        },
        {
          "id": "rc-db-cluster-003",
          "type": "application_bug",
          "description": "新部署的批处理作业导致数据库过载",
          "confidence": 0.35,
          "evidence": [
            {
              "type": "temporal",
              "description": "批处理作业部署时间接近故障时间",
              "weight": 0.6
            }
          ],
          "assessment": "时间相关性较弱，且无法解释网络丢包现象",
          "relationship_to_primary": "coincidental"
        },
        {
          "id": "rc-db-cluster-004",
          "type": "storage_performance",
          "description": "存储性能问题导致数据库响应慢",
          "confidence": 0.28,
          "evidence": [
            {
              "type": "metric",
              "description": "磁盘IO等待时间35%",
              "weight": 0.5
            }
          ],
          "assessment": "IO等待在正常范围内，不是根本原因",
          "relationship_to_primary": "unrelated"
        }
      ],
      "cross_system_insights": {
        "network_analysis": {
          "problem_scope": "VLAN-100内部通信",
          "affected_paths": ["master↔slave1", "applications↔master"],
          "healthy_paths": ["master↔slave2"],
          "diagnosis": "交换机固件更新导致特定VLAN包处理异常"
        },
        "database_analysis": {
          "primary_issue": "连接池压力",
          "secondary_issues": ["复制中断", "查询排队"],
          "resource_status": "adequate",
          "diagnosis": "数据库运行正常，问题来自外部"
        },
        "application_analysis": {
          "impact_pattern": "连接建立失败",
          "error_types": ["timeout", "connection_refused"],
          "retry_pattern": "exponential_backoff",
          "diagnosis": "应用行为正常，响应外部故障"
        },
        "infrastructure_analysis": {
          "load_balancer_behavior": "failover_to_master",
          "monitoring_gaps": "network_switch_health",
          "dependency_chain": "switch→network→database→loadbalancer→applications",
          "diagnosis": "基础设施级联故障"
        }
      },
      "algorithm_results": {
        "causal_graph": {
          "top_root_cause": "network_partition",
          "causal_strength": 0.89,
          "graph_nodes": 15,
          "graph_edges": 28,
          "critical_path": "switch→network→database→applications"
        },
        "bayesian": {
          "top_root_cause": "network_partition",
          "probability": 0.87,
          "network_layers": 4,
          "evidence_nodes": 8,
          "hypothesis_nodes": 7
        },
        "temporal_analysis": {
          "top_root_cause": "network_partition",
          "time_correlation": 0.94,
          "event_sequence": ["network_change", "packet_loss", "db_errors", "app_errors"],
          "lag_analysis": "consistent_15_minute_lag"
        },
        "historical_matching": {
          "best_match": "case-2025-10-15-002",
          "similarity_score": 0.91,
          "historical_root_cause": "switch_firmware_issue",
          "matched_pattern": "network_maintenance→database_connectivity",
          "historical_resolution": "rollback_switch_firmware"
        }
      }
    },
    "recommendations": [
      {
        "id": "rec-db-001",
        "priority": "immediate",
        "action": "暂停网络交换机固件更新",
        "description": "立即停止正在进行的交换机固件更新，防止问题恶化",
        "steps": [
          "1. 联系网络团队暂停固件更新",
          "2. 回滚到之前的稳定固件版本",
          "3. 验证网络连接恢复",
          "4. 监控数据库连接状态"
        ],
        "estimated_time": "15分钟",
        "risk": "low",
        "expected_impact": "立即停止网络丢包，开始恢复过程",
        "owner": "network_team",
        "verification": "网络丢包率降至正常水平（<1%）"
      },
      {
        "id": "rec-db-002",
        "priority": "immediate",
        "action": "临时调整数据库连接路由",
        "description": "将应用连接从主库分流到健康的从库2",
        "steps": [
          "1. 更新负载均衡器配置",
          "2. 将读流量导向从库2",
          "3. 验证从库2负载能力",
          "4. 监控应用连接恢复"
        ],
        "estimated_time": "10分钟",
        "risk": "medium",
        "expected_impact": "立即减轻主库压力，恢复应用连接",
        "owner": "dba_team",
        "verification": "主库连接数下降50%以上"
      },
      {
        "id": "rec-db-003",
        "priority": "short_term",
        "action": "修复数据库复制",
        "description": "在解决网络问题后，修复中断的数据库复制",
        "steps": [
          "1. 等待网络恢复稳定",
          "2. 停止从库1的复制线程",
          "3. 重新配置复制参数",
          "4. 启动复制并监控同步状态"
        ],
        "estimated_time": "30分钟",
        "risk": "medium",
        "expected_impact": "恢复完整的数据库集群功能",
        "prerequisites": "网络问题已解决",
        "owner": "dba_team"
      },
      {
        "id": "rec-db-004",
        "priority": "medium_term",
        "action": "实施网络变更影响评估流程",
        "description": "建立网络变更前的数据库影响评估机制",
        "steps": [
          "1. 定义网络变更评估清单",
          "2. 建立变更协调流程",
          "3. 实施预变更测试",
          "4. 设置变更回滚预案"
        ],
        "estimated_time": "2天",
        "risk": "low",
        "expected_impact": "预防类似网络变更导致的数据库故障",
        "owner": "change_management"
      },
      {
        "id": "rec-db-005",
        "priority": "long_term",
        "action": "增强跨系统监控和告警",
        "description": "建立网络-数据库-应用链路的综合监控",
        "steps": [
          "1. 实现网络健康度到数据库监控的关联",
          "2. 设置跨系统故障传播告警",
          "3. 建立基础设施依赖关系图",
          "4. 实施自动根因分析集成"
        ],
        "estimated_time": "1周",
        "risk": "low",
        "expected_impact": "提前发现和预防跨系统故障",
        "owner": "sre_team"
      }
    ],
    "performance": {
      "algorithm_execution_times": {
        "causal_graph": 45.2,
        "bayesian": 32.8,
        "temporal_analysis": 25.3,
        "historical_matching": 18.5,
        "cross_system_integration": 15.2
      },
      "total_analysis_time": 125.8,
      "memory_usage_mb": 850,
      "cpu_usage_percent": 68.5,
      "data_processed_mb": 45.2,
      "systems_analyzed": 4
    }
  },
  "metadata": {
    "skill_name": "root-cause-analysis",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:12:05Z",
    "execution_mode": "advanced",
    "analysis_config": {
      "algorithms_used": ["causal_graph", "bayesian", "historical_matching", "temporal_analysis"],
      "confidence_threshold": 0.65,
      "historical_data_enabled": true,
      "cross_system_analysis": true,
      "max_hypotheses": 7
    },
    "quality_indicators": {
      "data_completeness": "high",
      "evidence_correlation": "strong",
      "algorithm_consensus": "high",
      "historical_relevance": "high",
      "cross_system_coverage": "comprehensive"
    },
    "insights": {
      "key_finding": "网络基础设施变更是根本原因",
      "surprising_pattern": "故障完美遵循网络拓扑边界",
      "missed_monitoring": "缺乏交换机健康度到数据库监控的关联",
      "improvement_opportunity": "需要跨团队变更协调流程"
    }
  }
}
```

### 关键验证点

1. **根因准确性**：网络分区被正确识别为跨系统故障的根本原因
2. **置信度水平**：0.88的高置信度支持决策
3. **证据链完整性**：时间、拓扑、日志、指标多维度证据
4. **因果关系清晰**：7步清晰的跨系统因果链
5. **算法一致性**：所有4种算法一致指向网络问题
6. **历史支持**：匹配到相似历史案例
7. **修复建议可行性**：分优先级的具体可执行建议

## 故障排除

### 复杂场景问题解决

#### 问题1：跨系统数据不一致
**症状**：不同系统的监控数据时间不同步或指标矛盾

**解决方法**：
- 使用统一的时间戳服务
- 实施数据对齐和清洗
- 建立数据质量检查
- 对矛盾数据赋予较低权重

#### 问题2：因果关系模糊
**症状**：多个可能的根因，因果关系不明确

**解决方法**：
- 增加时间序列分析精度
- 使用干预分析（如果可能）
- 收集更多上下文数据
- 咨询领域专家

#### 问题3：算法结果冲突
**症状**：不同算法得出不同的根因结论

**解决方法**：
- 检查算法假设是否适用
- 增加算法权重调整
- 使用元学习整合结果
- 人工审查冲突点

#### 问题4：历史数据不足
**症状**：全新类型的故障，无历史匹配

**解决方法**：
- 使用相似性匹配而非精确匹配
- 依赖其他算法更多
- 记录当前案例供未来使用
- 结合专家知识

### 高级调试技巧

1. **分阶段分析**：
```bash
# 第一阶段：快速分析
claude witty-diagnosis:root-cause-analysis --quick-analysis ...

# 第二阶段：深度分析
claude witty-diagnosis:root-cause-analysis --deep-analysis ...
```

2. **假设验证**：
```bash
# 测试特定假设
claude witty-diagnosis:root-cause-analysis --test-hypothesis "network_partition" ...

# 对比不同假设
claude witty-diagnosis:root-cause-analysis --compare-hypotheses "network_partition,database_overload" ...
```

3. **可视化分析**：
```bash
# 生成因果关系图
claude witty-diagnosis:root-cause-analysis --generate-visualization ...

# 导出分析过程
claude witty-diagnosis:root-cause-analysis --export-analysis-steps ...
```

4. **性能优化**：
```bash
# 限制分析范围
claude witty-diagnosis:root-cause-analysis --limit-scope "last_2_hours" ...

# 使用采样数据
claude witty-diagnosis:root-cause-analysis --sample-data 0.5 ...
```

## 经验总结

### 成功关键因素
1. **数据整合能力**：成功整合网络、数据库、应用、系统多维度数据
2. **跨系统视角**：不局限于单个系统，分析整个技术栈
3. **时间序列分析**：准确的时间相关性分析锁定根本原因
4. **拓扑感知**：理解系统架构和网络拓扑
5. **变更关联**：将故障与最近的系统变更关联

### 改进建议
1. **数据标准化**：建立跨系统的统一数据模型
2. **监控集成**：实现基础设施监控与应用监控的关联
3. **变更管理**：加强跨团队变更协调和影响评估
4. **知识积累**：系统化积累跨系统故障案例
5. **自动化程度**：提高根因分析的自动化程度

### 最佳实践
1. **预防性分析**：在重大变更前执行预测性根因分析
2. **演练和测试**：定期进行跨系统故障演练
3. **工具集成**：将根因分析集成到监控和告警系统
4. **团队协作**：建立跨职能团队的根因分析流程
5. **持续改进**：基于分析结果持续优化系统和流程

### 扩展应用场景
1. **容量规划**：基于根因分析结果进行容量规划
2. **架构优化**：识别架构脆弱点并进行优化
3. **监控优化**：优化监控覆盖和告警策略
4. **应急预案**：制定更有效的应急预案
5. **团队培训**：基于真实案例进行团队培训

---

*示例版本：1.0.0*
*创建日期：2026-02-03*
*适用场景：跨系统复杂故障根因分析*