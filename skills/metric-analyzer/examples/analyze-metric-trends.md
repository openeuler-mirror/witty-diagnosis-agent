# 指标趋势分析示例

## 场景描述

企业数据库服务器需要定期进行性能趋势分析，以识别潜在的性能退化问题，预测未来资源需求，并支持容量规划决策。本示例展示如何使用metric-analyzer技能进行多维度的指标趋势分析，包括长期趋势识别、周期性分析、异常检测和容量预测。

## 前置条件

### 系统要求
- 欧拉OS 2.0或更高版本
- 已安装witty-diagnosis-agent
- 数据库服务器（MySQL/PostgreSQL/Oracle等）
- 至少30天的历史性能数据

### 数据准备
1. **收集历史指标数据**：
   ```bash
   # 收集30天的性能指标数据（每天收集一次）
   for i in {1..30}; do
     claude witty-diagnosis:data-collector \
       --session-id "db-metrics-day-$i" \
       --target system \
       --data-sources metrics \
       --metric-interval 60 \
       --metric-samples 5 \
       --output-format json \
       --output-file "/tmp/db-metrics-day-$i.json"
     sleep 86400  # 等待一天
   done
   ```

2. **合并历史数据**：
   ```bash
   # 创建历史数据汇总文件
   cat /tmp/db-metrics-day-*.json | jq -s '{historical_metrics: .}' > /tmp/db-metrics-30days.json
   ```

3. **数据质量检查**：
   - 确保时间戳连续性和准确性
   - 验证指标数据的完整性和一致性
   - 处理缺失值和异常值

### 分析目标
1. **识别性能趋势**：分析CPU、内存、磁盘、网络的使用趋势
2. **检测周期性模式**：识别日、周、月等周期性规律
3. **预测未来需求**：基于历史趋势预测未来30天的资源需求
4. **识别异常模式**：检测性能退化或异常波动
5. **生成容量建议**：提供具体的容量规划建议

## 执行步骤

### 步骤1：配置趋势分析参数

创建趋势分析配置文件 `trend-analysis-config.json`：

```json
{
  "session_id": "db-trend-analysis-001",
  "data_source": {
    "type": "historical",
    "path": "/tmp/db-metrics-30days.json",
    "time_range": {
      "start": "2026-01-01T00:00:00Z",
      "end": "2026-01-30T23:59:59Z"
    }
  },
  "parameters": {
    "analysis_type": "comprehensive",
    "metrics_to_analyze": ["cpu", "memory", "disk", "network", "database"],
    "trend_analysis_config": {
      "methods": ["linear_regression", "moving_average", "seasonal_decomposition"],
      "seasonality_periods": ["daily", "weekly"],
      "anomaly_detection": {
        "method": "statistical",
        "confidence_level": 0.95,
        "window_size": 7
      },
      "change_point_detection": true,
      "forecasting": {
        "horizon_days": 30,
        "methods": ["arima", "exponential_smoothing"],
        "confidence_intervals": [0.8, 0.95]
      }
    },
    "capacity_analysis_config": {
      "warning_threshold": 70,
      "critical_threshold": 85,
      "growth_assumption": "conservative",
      "business_growth_rate": 0.15,
      "planning_horizon": {
        "short_term": 30,
        "medium_term": 90,
        "long_term": 180
      }
    },
    "comparison_config": {
      "baseline_period": "first_week",
      "reference_points": ["industry_average", "sla_targets"],
      "performance_degradation_threshold": 0.1
    },
    "output_config": {
      "format": "html",
      "include_visualizations": true,
      "visualization_types": ["trend_lines", "seasonal_plots", "forecast_charts", "heatmaps"],
      "report_sections": ["executive_summary", "detailed_analysis", "recommendations", "appendices"]
    }
  },
  "metadata": {
    "environment": "production",
    "server_role": "database-primary",
    "database_type": "mysql",
    "database_version": "8.0",
    "data_size_tb": 5.2,
    "transaction_rate": "high",
    "business_criticality": "critical",
    "analysis_purpose": "quarterly_performance_review"
  }
}
```

### 步骤2：执行趋势分析

执行全面的趋势分析：

```bash
claude witty-diagnosis:metric-analyzer \
  --config-file trend-analysis-config.json \
  --output-format html \
  --output-file /tmp/db-trend-analysis-report.html \
  --include-visualizations \
  --verbosity info
```

### 步骤3：分析关键发现

分析完成后，检查HTML报告中的关键部分：

#### 3.1 执行摘要
```html
<!-- 报告中的执行摘要部分 -->
<div class="executive-summary">
  <h2>执行摘要</h2>
  <div class="key-findings">
    <h3>关键发现</h3>
    <ul>
      <li><strong>总体趋势</strong>: 系统性能呈现稳定上升趋势，月均增长2.3%</li>
      <li><strong>主要瓶颈</strong>: 内存使用率增长最快，月均增长5.8%</li>
      <li><strong>周期性模式</strong>: 明显的日周期和周周期模式</li>
      <li><strong>异常检测</strong>: 检测到3次性能异常事件</li>
      <li><strong>容量风险</strong>: 内存将在45天内达到警告阈值</li>
    </ul>
  </div>
  <div class="recommendations-summary">
    <h3>建议摘要</h3>
    <table>
      <tr><th>优先级</th><th>建议</th><th>时间线</th><th>预期影响</th></tr>
      <tr><td>高</td><td>增加16GB内存</td><td>30天内</td><td>降低内存压力30%</td></tr>
      <tr><td>中</td><td>优化数据库索引</td><td>60天内</td><td>提升查询性能20%</td></tr>
      <tr><td>低</td><td>实施查询缓存</td><td>90天内</td><td>减少CPU使用5%</td></tr>
    </table>
  </div>
</div>
```

#### 3.2 详细趋势分析

**CPU使用率趋势**：
```json
{
  "cpu_analysis": {
    "overall_trend": {
      "direction": "increasing",
      "slope": 0.023,
      "r_squared": 0.78,
      "monthly_growth_rate": 2.3,
      "confidence": 0.85
    },
    "seasonal_patterns": {
      "daily": {
        "amplitude": 15.2,
        "peak_hours": ["10:00", "15:00", "20:00"],
        "trough_hours": ["03:00", "14:00"],
        "pattern_type": "business_hours"
      },
      "weekly": {
        "weekday_avg": 42.5,
        "weekend_avg": 28.3,
        "busiest_day": "Wednesday",
        "quietest_day": "Sunday"
      }
    },
    "anomalies": [
      {
        "timestamp": "2026-01-15T14:30:00Z",
        "value": 68.5,
        "expected_range": [35, 50],
        "deviation": 37.0,
        "probable_cause": "批量数据导入作业",
        "duration": "2小时",
        "impact": "查询响应时间增加300%"
      }
    ],
    "change_points": [
      {
        "timestamp": "2026-01-10",
        "metric": "cpu_usage",
        "change_magnitude": 8.2,
        "change_type": "level_shift",
        "possible_triggers": ["应用版本升级", "用户数量增加"]
      }
    ]
  }
}
```

**内存使用趋势**：
```json
{
  "memory_analysis": {
    "trend_characteristics": {
      "current_usage_gb": 24.8,
      "total_memory_gb": 32.0,
      "utilization_percent": 77.5,
      "monthly_growth_gb": 1.2,
      "growth_rate_percent": 5.8
    },
    "forecast": {
      "30_day_forecast_gb": 28.4,
      "30_day_utilization": 88.8,
      "time_to_warning_threshold": "45天",
      "time_to_critical_threshold": "75天",
      "confidence_interval_80": [26.8, 30.0],
      "confidence_interval_95": [25.6, 31.2]
    },
    "pattern_analysis": {
      "memory_leak_suspicion": "low",
      "cache_efficiency": "high",
      "swap_usage_trend": "stable_low",
      "fragmentation_level": "moderate"
    }
  }
}
```

**磁盘I/O趋势**：
```json
{
  "disk_analysis": {
    "performance_trends": {
      "read_iops_trend": "stable",
      "write_iops_trend": "increasing",
      "latency_trend": "slight_increase",
      "throughput_trend": "increasing"
    },
    "capacity_analysis": {
      "current_usage_tb": 3.8,
      "total_capacity_tb": 8.0,
      "monthly_growth_tb": 0.15,
      "time_to_80_percent": "180天",
      "time_to_90_percent": "240天"
    },
    "performance_bottlenecks": {
      "primary_bottleneck": "write_latency",
      "peak_periods": ["备份窗口: 02:00-04:00", "报表生成: 08:00-10:00"],
      "suggested_optimizations": ["调整innodb_flush_log_at_trx_commit", "增加redo log大小"]
    }
  }
}
```

#### 3.3 容量预测和建议

**综合容量预测**：
```json
{
  "capacity_forecast": {
    "resource_timelines": {
      "memory_critical": {
        "estimated_date": "2026-03-20",
        "current_timeline": "75天",
        "mitigation_options": [
          {"action": "增加16GB内存", "timeline": "30天", "cost": "medium", "impact": "high"},
          {"action": "优化内存配置", "timeline": "15天", "cost": "low", "impact": "medium"}
        ]
      },
      "disk_space_warning": {
        "estimated_date": "2026-05-15",
        "current_timeline": "135天",
        "mitigation_options": [
          {"action": "清理历史数据", "timeline": "30天", "cost": "low", "impact": "medium"},
          {"action": "增加存储容量", "timeline": "60天", "cost": "high", "impact": "high"}
        ]
      }
    },
    "growth_scenarios": {
      "conservative": {
        "description": "基于历史趋势的保守预测",
        "monthly_growth_rates": {"cpu": 2.3, "memory": 5.8, "disk": 3.2},
        "risk_level": "low"
      },
      "moderate": {
        "description": "考虑业务增长15%的预测",
        "monthly_growth_rates": {"cpu": 4.1, "memory": 8.5, "disk": 5.8},
        "risk_level": "medium"
      },
      "aggressive": {
        "description": "考虑业务增长30%的预测",
        "monthly_growth_rates": {"cpu": 6.8, "memory": 12.3, "disk": 9.5},
        "risk_level": "high"
      }
    }
  }
}
```

**详细建议**：
```json
{
  "detailed_recommendations": [
    {
      "id": "rec-memory-001",
      "priority": "high",
      "category": "capacity",
      "title": "立即增加物理内存",
      "description": "内存使用率月增长5.8%，预计45天内达到警告阈值",
      "justification": {
        "current_state": "77.5%利用率，月增长1.2GB",
        "forecast": "30天后88.8%，45天后超过90%",
        "business_impact": "内存不足将导致查询性能下降和连接失败",
        "historical_evidence": "过去30天内存使用持续上升趋势明显"
      },
      "actions": [
        "采购并安装16GB DDR4内存条",
        "调整数据库缓冲池配置",
        "监控内存使用变化"
      ],
      "resources_required": {
        "budget": "中等",
        "time": "2周采购+4小时安装",
        "expertise": "系统管理员+DBA",
        "downtime": "计划性维护窗口"
      },
      "success_metrics": [
        "内存使用率降至70%以下",
        "查询响应时间改善20%",
        "连接失败率降至0.1%以下"
      ],
      "timeline": {
        "planning": "1周",
        "procurement": "2周",
        "implementation": "1天",
        "validation": "3天"
      }
    },
    {
      "id": "rec-performance-002",
      "priority": "medium",
      "category": "optimization",
      "title": "优化数据库索引和查询",
      "description": "检测到查询性能下降趋势，需要优化数据库性能",
      "justification": {
        "performance_trend": "查询响应时间月增长8%",
        "inefficient_queries": "识别出15个需要优化的慢查询",
        "index_fragmentation": "检测到中度索引碎片化"
      },
      "actions": [
        "分析并优化TOP 10慢查询",
        "重建碎片化索引",
        "调整查询缓存配置",
        "实施查询执行计划监控"
      ],
      "expected_benefits": [
        "查询性能提升20-30%",
        "CPU使用率降低3-5%",
        "减少锁等待时间"
      ]
    }
  ]
}
```

### 步骤4：生成可视化报告

metric-analyzer会生成包含丰富可视化的HTML报告：

1. **趋势线图**：展示各指标随时间的变化趋势
2. **季节性分解图**：显示趋势、季节性和残差分量
3. **预测图表**：展示未来30天的预测值和置信区间
4. **热力图**：显示指标在日/周维度的分布模式
5. **异常检测图**：高亮显示检测到的异常点
6. **容量预测仪表盘**：展示各资源的预测时间线

## 预期结果

### 分析报告结构
```
数据库性能趋势分析报告 (2026-01-01 至 2026-01-30)
├── 1. 执行摘要
│   ├── 1.1 关键发现
│   ├── 1.2 建议摘要
│   └── 1.3 风险等级评估
├── 2. 详细分析
│   ├── 2.1 CPU使用率分析
│   │   ├── 总体趋势
│   │   ├── 季节性模式
│   │   ├── 异常事件
│   │   └── 变化点检测
│   ├── 2.2 内存使用分析
│   │   ├── 使用趋势
│   │   ├── 容量预测
│   │   └── 模式分析
│   ├── 2.3 磁盘I/O分析
│   │   ├── 性能趋势
│   │   ├── 容量分析
│   │   └── 瓶颈识别
│   └── 2.4 网络性能分析
│       ├── 流量趋势
│       ├── 延迟分析
│       └── 连接数趋势
├── 3. 容量规划
│   ├── 3.1 资源时间线预测
│   ├── 3.2 增长场景分析
│   └── 3.3 成本效益分析
├── 4. 建议和行动计划
│   ├── 4.1 高优先级建议
│   ├── 4.2 中优先级建议
│   └── 4.3 长期优化建议
└── 附录
    ├── A. 分析方法说明
    ├── B. 数据质量评估
    └── C. 置信区间说明
```

### 成功标准
1. **分析完整性**：覆盖所有请求的指标和分析维度
2. **数据准确性**：基于准确的历史数据进行计算
3. **预测合理性**：预测结果在合理范围内且有置信区间
4. **建议可行性**：建议具体、可操作、有时限
5. **可视化质量**：图表清晰、信息丰富、易于理解
6. **执行性能**：分析过程在可接受时间内完成（<5分钟）

### 交付物
1. **HTML分析报告**：完整的可视化分析报告
2. **JSON详细数据**：原始分析数据供进一步处理
3. **执行摘要**：一页纸的关键发现和建议
4. **行动计划**：具体的实施步骤和时间表
5. **监控配置**：推荐的监控阈值和告警规则

## 故障排除

### 数据质量问题
**问题**：历史数据不完整或包含异常值
**解决方案**：
1. 使用数据清洗功能处理缺失值
2. 应用异常值检测和修正算法
3. 验证时间序列的连续性和一致性
4. 考虑使用插值方法补充缺失数据

### 趋势分析不准确
**问题**：趋势分析结果置信度低或不符合预期
**解决方案**：
1. 尝试不同的趋势分析方法
2. 调整季节性检测参数
3. 分段分析不同时间段的趋势
4. 验证数据是否满足分析方法的假设条件

### 预测不确定性高
**问题**：预测结果的置信区间过宽
**解决方案**：
1. 增加历史数据的时间范围
2. 使用组合预测方法提高准确性
3. 考虑外部因素（业务增长、季节性等）
4. 明确说明预测的局限性和假设条件

### 可视化生成失败
**问题**：HTML报告生成失败或图表显示异常
**解决方案**：
1. 检查可视化库的依赖和版本
2. 验证数据格式是否符合图表要求
3. 调整图表配置参数
4. 考虑生成静态图片替代交互式图表

## 最佳实践

### 数据管理
1. **定期收集**：建立自动化的指标收集机制
2. **数据质量**：实施数据质量监控和清洗流程
3. **长期存储**：建立历史数据归档和检索机制
4. **版本控制**：跟踪指标定义和分析方法的变化

### 分析方法
1. **多方法验证**：使用多种统计方法交叉验证结果
2. **分段分析**：对不同时间段采用不同的分析方法
3. **敏感性分析**：测试关键假设对结果的影响
4. **基准对比**：与行业基准和SLA目标对比

### 报告生成
1. **受众定制**：为不同受众生成不同详细程度的报告
2. **可视化原则**：遵循数据可视化最佳实践
3. **自动化生成**：建立定期报告自动生成机制
4. **版本管理**：保留历史报告供趋势对比

### 决策支持
1. **风险量化**：量化性能风险对业务的影响
2. **成本分析**：分析不同解决方案的成本效益
3. **优先级排序**：基于影响和紧迫性排序建议
4. **跟踪机制**：建立建议实施跟踪和效果评估

## 扩展应用

### 应用场景1：多系统对比分析
同时分析多个数据库服务器的性能趋势，识别集群中的异常节点和性能差异。

### 应用场景2：应用性能关联分析
结合业务指标（用户数、交易量）分析性能趋势的业务驱动因素。

### 应用场景3：变更影响分析
分析系统变更（升级、配置调整）对性能趋势的影响。

### 应用场景4：容量规划自动化
基于趋势分析结果自动触发容量扩展流程。

### 应用场景5：SLA合规性分析
分析性能趋势与SLA目标的符合程度，预测SLA违规风险。

---

*示例版本：1.0.0*
*最后更新：2026-02-03*
*适用技能版本：metric-analyzer 1.0.0+*