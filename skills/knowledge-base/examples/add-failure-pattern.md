# 添加故障模式示例

## 场景描述

系统管理员在欧拉OS生产环境中发现了一个新的性能问题模式：当系统内存使用率持续超过90%时，会出现进程响应延迟和OOM（Out of Memory）错误。管理员需要将这个故障模式添加到知识库中，以便诊断系统能够识别和解决类似问题。

## 前置条件

### 系统要求
- 欧拉OS 2.0或更高版本
- witty-diagnosis-agent已安装并运行
- 知识库管理技能已配置并可用

### 配置要求
- 知识库存储路径已正确配置
- 执行用户具有知识库写入权限
- 网络连接正常（如果使用远程存储）

### 数据准备
- 故障模式的详细描述和症状
- 相关的环境信息和配置
- 故障发生的时间范围和频率
- 已有的解决方案或缓解措施

## 执行步骤

### 步骤1：准备故障模式数据

创建故障模式数据文件 `memory-pressure-pattern.json`：

```json
{
  "pattern_id": "FP-2026-003",
  "name": "内存压力过高故障模式",
  "description": "系统内存使用率持续超过90%，导致进程响应延迟和OOM错误",
  "symptoms": [
    "系统内存使用率持续>90%",
    "swap使用率快速增长",
    "进程响应时间显著增加",
    "频繁出现OOM killer终止进程",
    "系统负载平均值异常增高"
  ],
  "causes": [
    "内存泄漏的应用程序",
    "配置不当的内存缓存",
    "并发用户数超过系统容量",
    "内存密集型任务集中执行",
    "虚拟内存配置不合理"
  ],
  "severity": "high",
  "confidence": 0.88,
  "environment": {
    "os": "EulerOS",
    "version": "2.0+",
    "architecture": ["x86_64", "aarch64"],
    "memory_size": ["8GB-", "16GB", "32GB", "64GB+"],
    "workload_type": ["web_server", "database", "application_server"]
  },
  "detection_methods": [
    "监控内存使用率趋势",
    "分析/proc/meminfo数据",
    "检查系统日志中的OOM事件",
    "监控进程内存使用情况",
    "分析性能指标异常"
  ],
  "impact_assessment": {
    "availability_impact": "high",
    "performance_impact": "critical",
    "recovery_complexity": "medium",
    "business_impact": "significant"
  },
  "prevention_measures": [
    "实施内存使用监控和告警",
    "优化应用程序内存管理",
    "配置合理的swap空间",
    "实施资源限制和配额",
    "定期进行容量规划"
  ],
  "references": [
    "欧拉OS内存管理最佳实践",
    "Linux内核OOM机制文档",
    "生产环境内存优化指南"
  ]
}
```

### 步骤2：执行知识存储操作

使用命令行工具添加故障模式到知识库：

```bash
# 方法1：直接使用命令行参数
claude witty-diagnosis:knowledge-base \
  --operation store \
  --knowledge-type failure_pattern \
  --session-id "add-memory-pattern-001" \
  --knowledge-data "$(cat memory-pressure-pattern.json)" \
  --validation-level strict \
  --verbosity info

# 方法2：使用JSON输入文件
claude witty-diagnosis:knowledge-base \
  --input-file memory-operation.json
```

其中 `memory-operation.json` 文件内容：

```json
{
  "session_id": "add-memory-pattern-001",
  "operation": "store",
  "knowledge_type": "failure_pattern",
  "parameters": {
    "timeout": 60,
    "verbosity": "info",
    "knowledge_data": {
      "pattern_id": "FP-2026-003",
      "name": "内存压力过高故障模式",
      "description": "系统内存使用率持续超过90%，导致进程响应延迟和OOM错误",
      "symptoms": [
        "系统内存使用率持续>90%",
        "swap使用率快速增长",
        "进程响应时间显著增加",
        "频繁出现OOM killer终止进程",
        "系统负载平均值异常增高"
      ],
      "causes": [
        "内存泄漏的应用程序",
        "配置不当的内存缓存",
        "并发用户数超过系统容量",
        "内存密集型任务集中执行",
        "虚拟内存配置不合理"
      ],
      "severity": "high",
      "confidence": 0.88,
      "environment": {
        "os": "EulerOS",
        "version": "2.0+",
        "architecture": ["x86_64", "aarch64"],
        "memory_size": ["8GB-", "16GB", "32GB", "64GB+"],
        "workload_type": ["web_server", "database", "application_server"]
      },
      "detection_methods": [
        "监控内存使用率趋势",
        "分析/proc/meminfo数据",
        "检查系统日志中的OOM事件",
        "监控进程内存使用情况",
        "分析性能指标异常"
      ],
      "impact_assessment": {
        "availability_impact": "high",
        "performance_impact": "critical",
        "recovery_complexity": "medium",
        "business_impact": "significant"
      },
      "prevention_measures": [
        "实施内存使用监控和告警",
        "优化应用程序内存管理",
        "配置合理的swap空间",
        "实施资源限制和配额",
        "定期进行容量规划"
      ],
      "references": [
        "欧拉OS内存管理最佳实践",
        "Linux内核OOM机制文档",
        "生产环境内存优化指南"
      ]
    },
    "validation_level": "strict",
    "output_format": "json",
    "include_metadata": true
  },
  "metadata": {
    "request_id": "req-add-pattern-001",
    "timestamp": "2026-02-03T18:00:00Z",
    "source": "production_incident_analysis",
    "contributor": {
      "id": "sysadmin-zhang",
      "role": "system_administrator",
      "team": "infrastructure"
    },
    "incident_details": {
      "incident_id": "INC-2026-0345",
      "occurrence_time": "2026-02-03T10:30:00Z",
      "duration_minutes": 45,
      "affected_services": ["web-app", "database", "cache"]
    }
  }
}
```

### 步骤3：验证操作结果

检查操作输出，确认故障模式已成功添加：

```json
{
  "status": "success",
  "session_id": "add-memory-pattern-001",
  "execution_time": 2.5,
  "results": {
    "operation": "store",
    "knowledge_type": "failure_pattern",
    "summary": {
      "operation_status": "completed",
      "knowledge_id": "FP-2026-003",
      "version": "1.0.0",
      "storage_location": "/var/lib/witty-diagnosis/knowledge/failure_patterns/FP-2026-003.json",
      "validation_passed": true,
      "associations_found": 3,
      "duplicate_check": "new_knowledge",
      "quality_score": 0.89
    },
    "knowledge_data": {
      "pattern_id": "FP-2026-003",
      "name": "内存压力过高故障模式",
      "description": "系统内存使用率持续超过90%，导致进程响应延迟和OOM错误",
      "symptoms": [...],
      "causes": [...],
      "severity": "high",
      "confidence": 0.88,
      "environment": {...},
      "detection_methods": [...],
      "impact_assessment": {...},
      "prevention_measures": [...],
      "references": [...],
      "metadata": {
        "created_at": "2026-02-03T18:00:00Z",
        "created_by": "sysadmin-zhang",
        "version": "1.0.0",
        "source": "production_incident_analysis",
        "last_validated": "2026-02-03T18:00:00Z",
        "validation_score": 0.92
      }
    },
    "associations": [
      {
        "target_knowledge_id": "SOL-2025-027",
        "target_type": "solution",
        "association_type": "solution_for",
        "strength": 0.91,
        "description": "内存优化和调优解决方案"
      },
      {
        "target_knowledge_id": "BP-2025-008",
        "target_type": "best_practice",
        "association_type": "implements",
        "strength": 0.85,
        "description": "内存监控和容量规划最佳实践"
      },
      {
        "target_knowledge_id": "FP-2025-038",
        "target_type": "failure_pattern",
        "association_type": "related_to",
        "strength": 0.76,
        "description": "与系统性能下降模式相关"
      }
    ],
    "validation_results": {
      "integrity_check": "passed",
      "consistency_check": "passed",
      "completeness_check": "passed",
      "validity_score": 0.90,
      "quality_score": 0.89,
      "warnings": [
        "建议添加具体的性能阈值数据",
        "考虑添加更多环境变量示例"
      ],
      "recommendations": [
        "添加历史发生频率统计",
        "补充具体的诊断命令示例",
        "添加相关监控指标定义"
      ]
    },
    "performance": {
      "storage_time_ms": 180,
      "validation_time_ms": 520,
      "association_time_ms": 380,
      "index_update_time_ms": 120,
      "total_operations": 6,
      "memory_usage_mb": 52
    }
  },
  "metadata": {
    "skill_name": "knowledge-base",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T18:00:03Z",
    "execution_mode": "standard",
    "knowledge_format_version": "1.0.0"
  }
}
```

### 步骤4：验证知识可检索性

验证新添加的故障模式可以通过检索操作找到：

```bash
# 检索内存相关的故障模式
claude witty-diagnosis:knowledge-base \
  --operation retrieve \
  --knowledge-type failure_pattern \
  --session-id "verify-memory-pattern-001" \
  --query-criteria '{"symptoms":["memory","OOM"],"severity":["high","critical"]}' \
  --max-results 5 \
  --similarity-threshold 0.6
```

预期检索结果应包含新添加的故障模式 `FP-2026-003`。

## 预期结果

### 成功指标
1. **操作成功**：存储操作返回`status: "success"`
2. **知识ID生成**：生成唯一的模式ID `FP-2026-003`
3. **数据完整性**：所有知识数据被正确存储
4. **关联建立**：自动建立与相关知识的关联关系
5. **验证通过**：知识验证通过，质量评分>0.8
6. **可检索性**：新知识可以通过检索操作找到

### 输出验证
- 检查输出中的`knowledge_id`是否正确
- 验证`storage_location`指向有效的文件路径
- 确认`associations`包含合理的关联关系
- 检查`validation_results`中的评分和建议
- 验证`metadata`包含正确的创建信息

### 性能要求
- 执行时间：< 5秒
- 内存使用：< 100MB
- 存储空间：知识文件大小 < 10KB
- 检索延迟：新知识可立即检索到

## 故障排除

### 常见问题1：权限不足
**问题现象**：
```json
{
  "status": "error",
  "error_code": "PERMISSION_DENIED",
  "error_message": "执行用户没有知识库写入权限"
}
```

**解决方法**：
1. 检查执行用户的权限
2. 确保知识库存储目录可写
3. 使用具有适当权限的用户执行
4. 调整目录权限：`chmod 755 /var/lib/witty-diagnosis/knowledge`

### 常见问题2：数据验证失败
**问题现象**：
```json
{
  "status": "error",
  "error_code": "VALIDATION_FAILED",
  "error_message": "知识数据验证失败，缺少必需字段"
}
```

**解决方法**：
1. 检查输入数据是否包含所有必需字段
2. 参考知识格式规范文档
3. 降低验证级别：`--validation-level basic`
4. 使用`--verbosity debug`查看详细验证信息

### 常见问题3：重复知识检测
**问题现象**：
```json
{
  "status": "success",
  "results": {
    "summary": {
      "duplicate_check": "similar_knowledge_exists",
      "existing_knowledge_id": "FP-2025-038"
    }
  }
}
```

**解决方法**：
1. 检查是否确实需要添加新知识
2. 考虑更新现有知识而不是添加新知识
3. 调整知识内容使其更具独特性
4. 使用`--force`参数强制添加（谨慎使用）

### 常见问题4：存储空间不足
**问题现象**：
```json
{
  "status": "error",
  "error_code": "STORAGE_FULL",
  "error_message": "知识库存储空间不足"
}
```

**解决方法**：
1. 清理不必要的知识数据
2. 扩展存储空间
3. 配置知识库使用其他存储位置
4. 启用知识压缩功能

### 调试技巧
1. **启用详细日志**：使用`--verbosity debug`查看详细执行过程
2. **检查中间文件**：查看临时文件和日志文件
3. **验证数据格式**：使用JSON验证工具检查输入数据
4. **分步执行**：先使用基本验证级别，再逐步提高
5. **查看系统日志**：检查系统日志中的相关错误信息

## 最佳实践

### 数据准备最佳实践
1. **详细描述**：提供清晰、具体的故障描述
2. **完整症状**：列出所有可能的症状表现
3. **环境信息**：明确适用的操作系统、版本和硬件环境
4. **严重性评估**：合理评估故障的严重程度
5. **置信度设置**：基于经验设置合理的置信度

### 操作执行最佳实践
1. **使用严格验证**：初始添加时使用`strict`验证级别
2. **包含丰富元数据**：提供详细的来源和贡献者信息
3. **批量操作**：多个相关模式可以批量添加
4. **定期验证**：定期验证知识库中的知识质量
5. **版本管理**：重要变更时创建新版本

### 维护最佳实践
1. **定期更新**：根据新经验更新现有知识
2. **质量评估**：定期评估知识质量和有效性
3. **关联维护**：维护知识间的关联关系
4. **备份策略**：定期备份知识库数据
5. **性能监控**：监控知识库操作的性能指标

## 扩展场景

### 场景1：批量添加故障模式
当从多个故障报告中提取模式时，可以批量添加：

```bash
# 创建批量操作文件 batch-operations.json
{
  "operations": [
    {
      "session_id": "batch-add-001",
      "operation": "store",
      "knowledge_type": "failure_pattern",
      "parameters": {
        "knowledge_data": { /* 模式1数据 */ }
      }
    },
    {
      "session_id": "batch-add-002",
      "operation": "store",
      "knowledge_type": "failure_pattern",
      "parameters": {
        "knowledge_data": { /* 模式2数据 */ }
      }
    }
  ]
}

# 执行批量操作
claude witty-diagnosis:knowledge-base --batch-file batch-operations.json
```

### 场景2：从现有系统导入知识
从现有监控系统或CMDB导入故障知识：

```bash
# 转换现有数据为标准格式
python convert-existing-knowledge.py --input incidents.json --output knowledge-base-format.json

# 导入到知识库
claude witty-diagnosis:knowledge-base --operation store --input-file knowledge-base-format.json
```

### 场景3：知识协作和评审
团队协作添加和评审故障模式：

1. **草稿创建**：创建知识草稿并提交评审
2. **团队评审**：团队成员评审知识内容
3. **修改完善**：根据反馈修改知识内容
4. **正式添加**：评审通过后正式添加到知识库
5. **版本记录**：记录评审过程和决策

---

*示例版本：1.0.0*
*最后更新：2026-02-03*