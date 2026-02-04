# CPU使用率监控示例

## 场景描述

生产环境中的Web服务器在业务高峰时段出现CPU使用率异常增高的问题。运维团队需要快速分析CPU使用情况，识别异常原因，并提供解决方案。本示例展示如何使用metric-analyzer技能进行CPU使用率的深度监控和分析。

## 前置条件

### 系统要求
- 欧拉OS 2.0或更高版本
- 已安装witty-diagnosis-agent
- 具有系统监控权限的用户

### 数据准备
1. 使用data-collector技能收集系统指标数据：
   ```bash
   claude witty-diagnosis:data-collector --target system --data-sources metrics --metric-interval 5 --metric-samples 12 --output-format json --output-file /tmp/cpu-metrics.json
   ```

2. 确保收集的指标数据包含：
   - CPU使用率（整体和各核心）
   - 系统负载（1分钟、5分钟、15分钟）
   - 进程级别的CPU使用情况
   - 至少30分钟的数据采样

### 配置要求
- 阈值配置：CPU使用率警告阈值70%，严重阈值85%
- 分析类型：阈值检测和趋势分析
- 对比基准：与前一天同时段对比

## 执行步骤

### 步骤1：准备分析输入

创建分析配置文件 `cpu-analysis-config.json`：

```json
{
  "session_id": "cpu-monitoring-001",
  "data_source": {
    "type": "file",
    "path": "/tmp/cpu-metrics.json",
    "format": "data-collector-output"
  },
  "parameters": {
    "analysis_type": "comprehensive",
    "metrics_to_analyze": ["cpu"],
    "threshold_config": {
      "cpu_usage": {
        "warning": 70,
        "critical": 85
      },
      "cpu_load_1min": {
        "warning": 2.0,
        "critical": 4.0
      },
      "cpu_load_5min": {
        "warning": 1.8,
        "critical": 3.5
      },
      "cpu_load_15min": {
        "warning": 1.5,
        "critical": 3.0
      }
    },
    "trend_window_hours": 1,
    "alert_severity_level": "warning",
    "comparison_period": "day_before",
    "include_process_analysis": true,
    "process_threshold_percent": 5.0
  },
  "metadata": {
    "environment": "production",
    "server_role": "web-server",
    "business_impact": "high",
    "monitoring_window": "business_hours_14-16",
    "expected_pattern": "gradual_increase"
  }
}
```

### 步骤2：执行指标分析

使用metric-analyzer技能执行分析：

```bash
claude witty-diagnosis:metric-analyzer --config-file cpu-analysis-config.json --output-format json --output-file /tmp/cpu-analysis-result.json
```

或者直接使用命令行参数：

```bash
claude witty-diagnosis:metric-analyzer \
  --session-id "cpu-monitoring-001" \
  --data-source "/tmp/cpu-metrics.json" \
  --analysis-type "comprehensive" \
  --metrics-to-analyze "cpu" \
  --threshold-config '{"cpu_usage": {"warning": 70, "critical": 85}}' \
  --trend-window-hours 1 \
  --comparison-period "day_before" \
  --include-process-analysis \
  --process-threshold-percent 5.0 \
  --verbosity "info"
```

### 步骤3：分析结果解读

分析完成后，检查输出结果的关键部分：

1. **阈值违规检测**：
   ```json
   {
     "threshold_analysis": {
       "violations": [
         {
           "metric": "cpu_usage",
           "current_value": 78.5,
           "threshold": 70.0,
           "violation_type": "warning",
           "duration_minutes": 45,
           "start_time": "2026-02-03T14:15:00Z",
           "end_time": "2026-02-03T15:00:00Z",
           "trend": "increasing",
           "rate_of_increase": 0.8
         }
       ]
     }
   }
   ```

2. **趋势分析结果**：
   ```json
   {
     "trend_analysis": {
       "cpu_usage": {
         "trend": "increasing",
         "slope": 0.15,
         "r_squared": 0.82,
         "periodicity": "daily_peak",
         "peak_time": "14:30-15:30",
         "forecast_30min": 82.3,
         "confidence": 0.85
       }
     }
   }
   ```

3. **进程级别分析**：
   ```json
   {
     "process_analysis": {
       "top_consumers": [
         {
           "pid": 12345,
           "name": "java",
           "user": "appuser",
           "cpu_percent": 35.2,
           "command": "/usr/bin/java -Xmx4g -jar webapp.jar",
           "duration_minutes": 40,
           "suggestion": "检查应用GC配置和线程池"
         },
         {
           "pid": 23456,
           "name": "nginx",
           "user": "nginx",
           "cpu_percent": 18.5,
           "command": "nginx: worker process",
           "duration_minutes": 45,
           "suggestion": "检查访问日志和并发连接数"
         }
       ],
       "total_processes_above_threshold": 8,
       "total_cpu_contribution": 78.3
     }
   }
   ```

4. **对比分析**：
   ```json
   {
     "comparison_analysis": {
       "day_before": {
         "cpu_usage_average": 52.3,
         "current_average": 78.5,
         "difference_percent": 50.1,
         "peak_time_similar": true,
         "pattern_change": "significant_increase"
       }
     }
   }
   ```

### 步骤4：生成预警和建议

基于分析结果，metric-analyzer会自动生成预警：

```json
{
  "alerts": [
    {
      "id": "cpu-alert-20260203-001",
      "timestamp": "2026-02-03T15:00:00Z",
      "severity": "warning",
      "metric": "cpu_usage",
      "current_value": 78.5,
      "threshold": 70.0,
      "message": "CPU使用率持续高于警告阈值45分钟，比昨天同期高50%",
      "context": {
        "time_period": "业务高峰时段(14:00-16:00)",
        "primary_contributors": ["java(35.2%)", "nginx(18.5%)"],
        "trend_direction": "持续上升",
        "forecast": "30分钟后可能达到82.3%"
      },
      "immediate_actions": [
        "检查高CPU进程：ps aux --sort=-%cpu | head -10",
        "分析Java应用GC日志：jstat -gcutil 12345 1000 10",
        "检查Nginx访问日志：tail -f /var/log/nginx/access.log | grep '5xx'",
        "监控系统负载：uptime && mpstat -P ALL 1 5"
      ],
      "investigation_steps": [
        "检查应用错误日志：grep -i 'error\\|exception\\|timeout' /var/log/webapp/*.log",
        "分析数据库查询性能：慢查询日志分析",
        "检查外部API调用延迟",
        "验证缓存命中率"
      ],
      "long_term_recommendations": [
        "优化Java应用JVM参数，调整GC策略",
        "考虑增加Nginx worker进程数",
        "实施应用性能监控(APM)",
        "评估水平扩展需求"
      ]
    }
  ]
}
```

## 预期结果

### 成功输出特征
1. **状态标识**：`"status": "success"`
2. **分析完整性**：包含阈值、趋势、进程和对比分析
3. **预警准确性**：预警信息准确反映问题严重程度
4. **建议实用性**：提供具体、可操作的解决建议
5. **性能指标**：执行时间合理（<30秒）

### 关键指标验证
- CPU使用率异常被正确识别
- 趋势分析准确预测未来走势
- 主要消耗进程被正确识别
- 与历史数据的对比分析有意义
- 预警严重级别与实际情况匹配

### 输出文件结构
```
/tmp/cpu-analysis-result.json
├── status: "success"
├── results.summary
│   ├── total_metrics_analyzed: 1
│   ├── alerts_generated: 1
│   └── analysis_completeness: "full"
├── results.analysis_details
│   ├── threshold_analysis
│   ├── trend_analysis
│   ├── process_analysis
│   └── comparison_analysis
├── results.alerts
│   └── [详细的预警信息]
└── metadata
    └── [技能版本和执行信息]
```

## 故障排除

### 常见问题1：数据收集不完整
**症状**：分析结果缺少关键指标或时间范围不完整
**解决方法**：
1. 验证data-collector执行是否成功
2. 检查指标收集间隔和采样次数
3. 确保有足够的历史数据用于对比分析
4. 重新执行数据收集，增加采样频率

### 常见问题2：阈值配置不合理
**症状**：预警过多或过少，不符合实际情况
**解决方法**：
1. 根据系统基线调整阈值配置
2. 考虑业务时段差异设置不同阈值
3. 使用动态阈值而非固定值
4. 参考行业基准和最佳实践

### 常见问题3：进程分析不准确
**症状**：无法识别主要CPU消耗进程
**解决方法**：
1. 确保data-collector收集了进程信息
2. 调整process_threshold_percent参数
3. 检查进程数据的时间戳对齐
4. 验证用户权限是否足够

### 常见问题4：趋势分析置信度低
**症状**：趋势分析结果置信度(r_squared)低于0.5
**解决方法**：
1. 增加trend_window_hours获取更多数据
2. 检查数据质量，排除异常值
3. 考虑使用不同的趋势分析算法
4. 分段分析不同时间段的趋势

### 调试技巧
1. **启用详细日志**：使用`--verbosity debug`参数
2. **分步执行**：先执行阈值检测，再执行趋势分析
3. **数据验证**：手动检查输入数据格式和内容
4. **参数调整**：逐步调整参数观察效果变化
5. **基准测试**：在已知正常系统上建立分析基准

## 最佳实践

### 监控策略
1. **分层监控**：结合系统级、进程级和应用级监控
2. **时段感知**：区分业务高峰和低谷时段的阈值
3. **趋势预警**：在达到阈值前基于趋势提前预警
4. **关联分析**：结合内存、磁盘、网络指标综合分析

### 配置优化
1. **动态阈值**：基于历史数据自动调整阈值
2. **智能基线**：学习系统正常行为模式建立基线
3. **异常模式库**：积累常见异常模式提高识别准确性
4. **自适应采样**：根据系统负载动态调整采样频率

### 集成建议
1. **与告警系统集成**：将预警推送到现有监控平台
2. **与自动化工具集成**：触发自动化的故障响应流程
3. **与知识库集成**：积累分析经验和解决方案
4. **与报表系统集成**：生成定期性能分析报告

### 性能考虑
1. **分析频率**：根据业务重要性设置合理的分析频率
2. **数据保留**：合理设置历史数据保留策略
3. **资源限制**：控制分析过程对系统资源的影响
4. **结果缓存**：对重复分析使用缓存结果提高效率

## 扩展场景

### 场景1：多服务器对比分析
同时分析多个服务器的CPU使用情况，识别集群中的异常节点。

### 场景2：应用性能关联分析
结合应用日志和业务指标，分析CPU使用率与业务流量的关系。

### 场景3：容量规划预测
基于历史趋势预测未来CPU需求，支持容量规划决策。

### 场景4：自动化优化
基于分析结果自动调整应用配置或系统参数。

---

*示例版本：1.0.0*
*最后更新：2026-02-03*
*适用技能版本：metric-analyzer 1.0.0+*