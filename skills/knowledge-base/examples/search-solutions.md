# 搜索解决方案示例

## 场景描述

欧拉OS生产环境中的数据库服务器出现性能问题，具体症状包括：查询响应时间显著增加、连接池耗尽、CPU使用率异常增高。运维团队需要从知识库中检索相关的解决方案，以快速诊断和解决问题。

## 前置条件

### 系统要求
- 欧拉OS 2.0或更高版本
- witty-diagnosis-agent已安装并运行
- 知识库管理技能已配置并可用
- 知识库中已存储相关解决方案知识

### 配置要求
- 知识库检索功能已启用
- 检索索引已建立并更新
- 执行用户具有知识库读取权限

### 数据准备
- 故障症状的详细描述
- 相关的环境信息（操作系统、数据库类型等）
- 问题发生的时间范围和影响程度
- 已尝试的初步排查步骤

## 执行步骤

### 步骤1：分析故障症状

收集和整理故障症状信息：

```json
{
  "observed_symptoms": [
    "数据库查询响应时间从平均50ms增加到500ms",
    "数据库连接池使用率达到95%以上",
    "CPU使用率从正常30%增加到80%",
    "磁盘IO等待时间增加",
    "出现连接超时错误日志"
  ],
  "environment_info": {
    "os": "EulerOS",
    "os_version": "2.5",
    "database_type": "MySQL",
    "database_version": "8.0",
    "hardware": {
      "cpu_cores": 16,
      "memory_gb": 64,
      "storage_type": "SSD"
    },
    "workload": {
      "type": "oltp",
      "concurrent_users": 500,
      "transaction_rate": "high"
    }
  },
  "timeline": {
    "start_time": "2026-02-03T14:30:00Z",
    "duration_hours": 2,
    "peak_time": "2026-02-03T15:00:00Z"
  },
  "impact": {
    "affected_services": ["web-application", "api-gateway", "reporting-service"],
    "business_impact": "high",
    "user_complaints": 15
  }
}
```

### 步骤2：构建检索查询

根据症状构建检索查询条件：

```bash
# 方法1：使用命令行参数构建精确查询
claude witty-diagnosis:knowledge-base \
  --operation retrieve \
  --knowledge-type solution \
  --session-id "search-db-solutions-001" \
  --query-criteria '{
    "category": "database",
    "symptoms": ["slow query", "high cpu", "connection pool"],
    "environment": {
      "os": "EulerOS",
      "database_type": "MySQL"
    },
    "severity": ["high", "critical"]
  }' \
  --max-results 10 \
  --similarity-threshold 0.7 \
  --output-format json \
  --verbosity info

# 方法2：使用JSON输入文件进行复杂查询
claude witty-diagnosis:knowledge-base --input-file search-request.json
```

`search-request.json` 文件内容：

```json
{
  "session_id": "search-db-solutions-001",
  "operation": "retrieve",
  "knowledge_type": "solution",
  "parameters": {
    "timeout": 30,
    "verbosity": "info",
    "query_criteria": {
      "category": "database",
      "subcategory": ["performance", "connection", "resource"],
      "symptoms": [
        "slow query performance",
        "high cpu usage",
        "connection pool exhaustion",
        "disk io wait increase",
        "query timeout errors"
      ],
      "environment": {
        "os": "EulerOS",
        "os_version": "2.0+",
        "database_type": ["MySQL", "MariaDB", "PostgreSQL"],
        "workload_type": ["oltp", "olap"]
      },
      "severity": ["medium", "high", "critical"],
      "effectiveness": {
        "min": 0.7
      },
      "implementation_complexity": ["low", "medium"]
    },
    "search_mode": "fuzzy",
    "max_results": 15,
    "similarity_threshold": 0.65,
    "ranking_strategy": "relevance_and_effectiveness",
    "output_format": "json",
    "include_metadata": true,
    "include_associations": true,
    "include_validation": false
  },
  "metadata": {
    "request_id": "req-search-solutions-001",
    "timestamp": "2026-02-03T15:30:00Z",
    "diagnosis_session": "diag-2026-0789",
    "problem_context": {
      "problem_type": "database_performance_degradation",
      "urgency": "high",
      "priority": "p1",
      "assigned_team": "database_operations"
    },
    "requester": {
      "id": "dba-li",
      "role": "database_administrator",
      "experience_level": "senior"
    }
  }
}
```

### 步骤3：执行检索操作

执行检索命令并分析结果：

```bash
# 执行检索
claude witty-diagnosis:knowledge-base --input-file search-request.json > search-results.json

# 查看结果摘要
cat search-results.json | jq '.results.summary'

# 提取解决方案列表
cat search-results.json | jq '.results.knowledge_items[] | {knowledge_id, name, effectiveness, similarity_score}'
```

### 步骤4：分析检索结果

典型的检索结果输出：

```json
{
  "status": "success",
  "session_id": "search-db-solutions-001",
  "execution_time": 1.8,
  "results": {
    "operation": "retrieve",
    "knowledge_type": "solution",
    "summary": {
      "total_found": 23,
      "returned_count": 10,
      "query_criteria": {
        "category": "database",
        "symptoms": ["slow query performance", "high cpu usage", "connection pool exhaustion"],
        "environment": {"os": "EulerOS"},
        "severity": ["medium", "high", "critical"]
      },
      "search_mode": "fuzzy",
      "similarity_threshold": 0.65,
      "ranking_strategy": "relevance_and_effectiveness",
      "search_time_ms": 1250,
      "ranking_time_ms": 320
    },
    "knowledge_items": [
      {
        "knowledge_id": "SOL-2025-042",
        "name": "MySQL查询性能优化方案",
        "description": "针对MySQL慢查询和高CPU使用率的综合优化方案",
        "category": "database",
        "subcategory": ["performance", "optimization"],
        "applicable_symptoms": [
          "slow query performance",
          "high cpu usage",
          "query timeout",
          "connection pool issues"
        ],
        "solution_steps": [
          "分析慢查询日志识别问题SQL",
          "优化索引策略和查询语句",
          "调整数据库配置参数",
          "实施查询缓存和结果缓存",
          "监控和调优连接池设置"
        ],
        "effectiveness": 0.88,
        "implementation_complexity": "medium",
        "estimated_time_minutes": 45,
        "risk_level": "low",
        "prerequisites": ["database access", "query logs", "monitoring tools"],
        "similarity_score": 0.92,
        "relevance_score": 0.89,
        "metadata": {
          "created_at": "2025-11-15T09:30:00Z",
          "updated_at": "2026-01-20T14:15:00Z",
          "success_rate": 0.85,
          "usage_count": 127,
          "average_resolution_time_minutes": 38,
          "contributor": "dba-expert-wang",
          "last_validated": "2026-01-20T14:15:00Z",
          "validation_score": 0.91
        }
      },
      {
        "knowledge_id": "SOL-2025-056",
        "name": "数据库连接池调优方案",
        "description": "解决数据库连接池耗尽和性能问题的调优方案",
        "category": "database",
        "subcategory": ["connection", "resource"],
        "applicable_symptoms": [
          "connection pool exhaustion",
          "connection timeout errors",
          "high connection creation rate",
          "connection leak symptoms"
        ],
        "solution_steps": [
          "分析连接池使用模式和峰值",
          "优化连接池配置参数",
          "实施连接泄漏检测",
          "配置连接超时和重试策略",
          "监控连接池健康状态"
        ],
        "effectiveness": 0.82,
        "implementation_complexity": "low",
        "estimated_time_minutes": 25,
        "risk_level": "very_low",
        "prerequisites": ["application configuration access", "monitoring access"],
        "similarity_score": 0.85,
        "relevance_score": 0.83,
        "metadata": {
          "created_at": "2025-12-03T11:20:00Z",
          "updated_at": "2026-01-10T10:45:00Z",
          "success_rate": 0.78,
          "usage_count": 89,
          "average_resolution_time_minutes": 22,
          "contributor": "devops-team",
          "last_validated": "2026-01-10T10:45:00Z"
        }
      },
      {
        "knowledge_id": "SOL-2026-008",
        "name": "欧拉OS上MySQL CPU优化方案",
        "description": "针对欧拉OS环境下MySQL CPU使用率过高的优化方案",
        "category": "database",
        "subcategory": ["performance", "os_integration"],
        "applicable_symptoms": [
          "high cpu usage on euleros",
          "system resource contention",
          "database and os interaction issues"
        ],
        "solution_steps": [
          "检查欧拉OS内核参数优化",
          "调整MySQL与OS资源分配",
          "优化IO调度器和文件系统",
          "实施CPU亲和性设置",
          "监控系统级资源使用"
        ],
        "effectiveness": 0.79,
        "implementation_complexity": "medium",
        "estimated_time_minutes": 35,
        "risk_level": "medium",
        "prerequisites": ["root access", "system tuning knowledge"],
        "similarity_score": 0.81,
        "relevance_score": 0.80,
        "metadata": {
          "created_at": "2026-01-25T16:40:00Z",
          "updated_at": "2026-02-01T09:15:00Z",
          "success_rate": 0.72,
          "usage_count": 15,
          "average_resolution_time_minutes": 32,
          "contributor": "euleros-specialist",
          "environment_specific": true,
          "os_specific": "EulerOS"
        }
      }
    ],
    "pagination": {
      "page": 1,
      "page_size": 10,
      "total_pages": 3,
      "has_next": true,
      "has_previous": false,
      "next_page_token": "page_2_token_abc123"
    },
    "recommendations": {
      "top_recommendation": "SOL-2025-042",
      "recommendation_reason": "最高相似度和有效性评分，涵盖主要症状",
      "alternative_recommendations": ["SOL-2025-056", "SOL-2026-008"],
      "combined_approach_suggested": true,
      "suggested_implementation_order": [
        "SOL-2025-056",
        "SOL-2025-042",
        "SOL-2026-008"
      ]
    },
    "performance": {
      "search_time_ms": 1250,
      "ranking_time_ms": 320,
      "results_processed": 23,
      "cache_hit_rate": 0.65,
      "memory_usage_mb": 68
    }
  },
  "metadata": {
    "skill_name": "knowledge-base",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T15:30:02Z",
    "execution_mode": "standard",
    "search_engine_version": "1.0.0"
  }
}
```

### 步骤5：评估和选择解决方案

基于检索结果进行评估：

```bash
# 评估解决方案的适用性
cat search-results.json | jq '
  .results.knowledge_items[] |
  select(.similarity_score >= 0.8) |
  {
    knowledge_id: .knowledge_id,
    name: .name,
    effectiveness: .effectiveness,
    complexity: .implementation_complexity,
    estimated_time: .estimated_time_minutes,
    risk: .risk_level,
    similarity: .similarity_score,
    relevance: .relevance_score
  }
'

# 生成解决方案比较报告
cat search-results.json | jq '
  "=== 数据库性能问题解决方案比较报告 ===",
  "生成时间: \(.metadata.timestamp)",
  "查询条件: \(.results.summary.query_criteria | tostring)",
  "",
  "推荐方案:",
  (.results.knowledge_items[] |
    "  - \(.knowledge_id): \(.name)",
    "    有效性: \(.effectiveness * 100)% 复杂度: \(.implementation_complexity)",
    "    预估时间: \(.estimated_time_minutes)分钟 风险: \(.risk_level)",
    "    相似度: \(.similarity_score * 100)% 相关度: \(.relevance_score * 100)%",
    ""
  ),
  "建议实施顺序:",
  (.results.recommendations.suggested_implementation_order[] | "  - \(.)")
'
```

## 预期结果

### 成功指标
1. **检索成功**：操作返回`status: "success"`
2. **结果相关性**：返回的解决方案与查询症状高度相关
3. **排序合理**：结果按相关性和有效性合理排序
4. **信息完整**：包含解决方案的详细信息和使用数据
5. **性能良好**：检索时间在可接受范围内

### 输出验证
- 检查`total_found`和`returned_count`的合理性
- 验证`similarity_score`反映实际相关性
- 确认`metadata`包含有用的使用统计
- 检查`recommendations`提供有价值的指导
- 验证分页功能正常工作

### 性能要求
- 检索时间：< 3秒（对于中等规模知识库）
- 内存使用：< 150MB
- 结果数量：可配置，默认10-20个
- 排序延迟：< 500ms

## 高级检索技巧

### 技巧1：组合查询条件
```json
{
  "query_criteria": {
    "$and": [
      {
        "category": "database",
        "subcategory": {"$in": ["performance", "connection"]}
      },
      {
        "$or": [
          {"symptoms": {"$contains": "slow query"}},
          {"symptoms": {"$contains": "high cpu"}}
        ]
      },
      {
        "environment.os": "EulerOS",
        "effectiveness": {"$gte": 0.7}
      }
    ]
  }
}
```

### 技巧2：时间范围过滤
```json
{
  "query_criteria": {
    "category": "database",
    "metadata.created_at": {
      "$gte": "2025-01-01T00:00:00Z",
      "$lte": "2026-02-03T23:59:59Z"
    }
  }
}
```

### 技巧3：使用统计过滤
```json
{
  "query_criteria": {
    "category": "database",
    "metadata.success_rate": {"$gte": 0.8},
    "metadata.usage_count": {"$gte": 50}
  }
}
```

### 技巧4：环境特定过滤
```json
{
  "query_criteria": {
    "category": "database",
    "$or": [
      {"environment.os": "EulerOS"},
      {"environment.os": {"$exists": false}}
    ],
    "metadata.environment_specific": {"$ne": true}
  }
}
```

## 故障排除

### 常见问题1：无结果返回
**问题现象**：
```json
{
  "status": "success",
  "results": {
    "summary": {
      "total_found": 0,
      "returned_count": 0
    }
  }
}
```

**解决方法**：
1. 降低相似度阈值：`--similarity-threshold 0.5`
2. 扩大查询范围：减少查询条件限制
3. 使用模糊搜索：`--search-mode fuzzy`
4. 检查知识库内容：确认相关解决方案已存储
5. 调整查询关键词：使用更通用的症状描述

### 常见问题2：结果相关性低
**问题现象**：返回的解决方案相似度评分低（<0.6）

**解决方法**：
1. 优化查询条件：提供更具体的症状描述
2. 使用同义词扩展：系统自动扩展相关术语
3. 调整排序策略：`--ranking-strategy effectiveness_first`
4. 手动筛选结果：基于其他字段（如effectiveness）筛选
5. 反馈改进：提供反馈帮助改进检索算法

### 常见问题3：检索性能慢
**问题现象**：检索时间超过5秒

**解决方法**：
1. 减少返回结果数：`--max-results 5`
2. 优化查询条件：避免过于复杂的组合查询
3. 启用缓存：确保检索缓存已启用
4. 检查索引状态：重建或优化检索索引
5. 分页查询：使用分页减少单次处理量

### 常见问题4：权限问题
**问题现象**：
```json
{
  "status": "error",
  "error_code": "ACCESS_DENIED",
  "error_message": "没有知识库读取权限"
}
```

**解决方法**：
1. 检查执行用户权限
2. 验证知识库访问配置
3. 使用具有适当权限的用户
4. 检查访问控制列表配置

### 调试技巧
1. **启用详细输出**：`--verbosity debug`查看检索过程
2. **分析查询计划**：查看查询解析和索引使用情况
3. **检查缓存命中**：分析缓存使用率和效果
4. **监控资源使用**：检查CPU、内存、IO使用情况
5. **测试简单查询**：先用简单查询测试基本功能

## 最佳实践

### 查询构建最佳实践
1. **具体症状**：提供具体、详细的症状描述
2. **环境信息**：包含操作系统、软件版本等环境信息
3. **合理范围**：设置合理的相似度阈值和结果数量
4. **组合查询**：使用逻辑运算符组合多个条件
5. **逐步细化**：先宽泛查询，再逐步细化

### 结果评估最佳实践
1. **多维度评估**：综合考虑相似度、有效性、复杂度
2. **元数据参考**：参考使用统计和成功率数据
3. **环境匹配**：优先选择环境匹配的解决方案
4. **风险评估**：考虑实施风险和复杂度
5. **组合方案**：考虑多个解决方案的组合使用

### 性能优化最佳实践
1. **合理分页**：使用分页减少单次返回数据量
2. **缓存利用**：利用检索缓存提高重复查询性能
3. **索引维护**：定期维护和优化检索索引
4. **查询简化**：避免过于复杂的查询条件
5. **异步处理**：对于复杂查询考虑异步处理

## 扩展场景

### 场景1：实时诊断集成
在诊断流程中自动检索解决方案：

```bash
# 诊断流程中集成知识检索
claude witty-diagnosis:fault-localization \
  --symptoms "slow query,high cpu,connection pool" \
  --environment "EulerOS 2.5,MySQL 8.0" \
  --knowledge-integration true \
  --auto-retrieve-solutions true
```

### 场景2：解决方案推荐系统
基于历史数据推荐最佳解决方案：

```bash
# 基于相似历史问题推荐解决方案
claude witty-diagnosis:knowledge-base \
  --operation recommend \
  --problem-description "数据库性能下降，查询变慢" \
  --historical-context "similar_incidents.json" \
  --recommendation-count 3 \
  --confidence-threshold 0.8
```

### 场景3：知识库质量分析
分析知识库中解决方案的质量和覆盖度：

```bash
# 分析解决方案知识库
claude witty-diagnosis:knowledge-base \
  --operation analyze \
  --analysis-type "solution_coverage" \
  --categories "database,network,storage" \
  --output-format report
```

---

*示例版本：1.0.0*
*最后更新：2026-02-03*