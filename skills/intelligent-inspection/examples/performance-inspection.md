# 性能巡检示例

## 场景描述

本示例展示如何使用intelligent-inspection技能进行深度性能巡检。性能巡检专注于系统性能指标的深度分析、瓶颈识别和容量规划，适用于性能优化、容量评估和故障预防场景。

**适用场景**：
- 系统性能下降问题诊断
- 容量规划和资源扩容评估
- 应用部署前的性能基准测试
- 性能调优效果验证
- 周期性性能健康检查

**检查重点**：
1. CPU使用率和负载分析
2. 内存使用模式和泄漏检测
3. 磁盘IO性能和容量趋势
4. 网络带宽和延迟分析
5. 应用响应时间和吞吐量
6. 系统瓶颈识别和根因分析

## 前置条件

### 系统要求
- 欧拉OS 2.0或更高版本
- 至少4GB可用内存（用于深度分析）
- 至少500MB磁盘空间用于性能数据存储
- 系统正常运行至少7天（用于趋势分析）

### 配置要求
- data-collector技能已安装并配置高频率数据收集
- metric-analyzer技能已安装并配置历史数据存储
- intelligent-inspection技能已安装性能分析插件
- 执行用户具有性能数据收集权限

### 数据准备
- 确认metric-analyzer中有至少7天的历史性能数据
- 准备业务负载信息（如用户量、交易量）
- 了解系统性能SLA要求
- 准备性能测试工具（如压测工具）

## 执行步骤

### 步骤1：准备性能巡检配置

创建性能巡检配置文件 `performance-inspection-config.json`：

```json
{
  "session_id": "performance-inspection-20260203",
  "inspection_type": "performance",
  "parameters": {
    "timeout": 900,
    "verbosity": "info",
    "inspection_depth": "deep",
    "check_categories": [
      "performance",
      "storage",
      "network",
      "application"
    ],
    "alert_threshold": {
      "critical": 85,
      "warning": 70,
      "info": 50
    },
    "trend_analysis_days": 30,
    "generate_report": true,
    "send_alerts": true,
    "compare_with_baseline": true,
    "output_format": "html",
    "performance_analysis": {
      "include_peak_analysis": true,
      "include_bottleneck_analysis": true,
      "include_capacity_planning": true,
      "include_application_performance": true,
      "sampling_interval": 5,
      "analysis_period": "24h"
    }
  },
  "metadata": {
    "request_id": "perf-inspection-001",
    "timestamp": "2026-02-03T14:00:00Z",
    "environment": "production",
    "scheduled": false,
    "trigger_reason": "performance_degradation",
    "business_impact": "high",
    "sla_requirements": {
      "response_time": "200ms",
      "availability": "99.9%",
      "throughput": "1000 tps"
    },
    "application_context": {
      "name": "ecommerce-platform",
      "version": "2.5.0",
      "user_count": "5000 concurrent",
      "transaction_volume": "10000/hour"
    }
  }
}
```

### 步骤2：执行性能巡检命令

使用命令行工具执行深度性能巡检：

```bash
# 方式1：完整性能巡检
claude witty-diagnosis:intelligent-inspection \
  --session-id "performance-inspection-20260203" \
  --inspection-type performance \
  --inspection-depth deep \
  --check-categories performance storage network application \
  --trend-analysis-days 30 \
  --timeout 900 \
  --generate-report \
  --output-format html \
  --performance-analysis

# 方式2：针对性性能检查（CPU和内存）
claude witty-diagnosis:intelligent-inspection \
  --session-id "cpu-memory-analysis-$(date +%Y%m%d)" \
  --inspection-type performance \
  --check-categories performance \
  --parameters '{
    "performance_analysis": {
      "focus_areas": ["cpu", "memory"],
      "include_leak_detection": true,
      "include_thread_analysis": true
    }
  }'

# 方式3：容量规划专项检查
claude witty-diagnosis:intelligent-inspection \
  --session-id "capacity-planning-$(date +%Y%m%d)" \
  --inspection-type performance \
  --check-categories performance storage \
  --trend-analysis-days 90 \
  --parameters '{
    "performance_analysis": {
      "include_capacity_planning": true,
      "forecast_period": "180d",
      "growth_assumption": "conservative"
    }
  }'
```

### 步骤3：监控执行过程

性能巡检执行过程中需要特别关注资源使用：

```bash
# 监控巡检进程资源使用
watch -n 2 "ps -eo pid,pcpu,pmem,cmd --sort=-pcpu | head -10 | grep intelligent-inspection"

# 监控系统性能指标（实时对比）
sar -u 2 10          # CPU使用率
sar -r 2 10          # 内存使用
sar -b 2 10          # IO统计
sar -n DEV 2 10      # 网络统计

# 检查分析进度
tail -f /var/log/witty-diagnosis/performance-inspection.log | \
  grep -E "ANALYSIS|BOTTLENECK|TREND|CAPACITY"
```

### 步骤4：分析性能巡检结果

巡检完成后，深度分析性能数据：

```bash
# 保存HTML报告
claude witty-diagnosis:intelligent-inspection \
  --config-file performance-inspection-config.json \
  --output-file /var/www/html/performance-report-$(date +%Y%m%d).html

# 提取关键性能指标
jq '.results.trend_analysis.performance_trends' performance-result.json
jq '.results.issues.critical[] | select(.category=="performance")' performance-result.json
jq '.results.capacity_planning' performance-result.json

# 生成性能摘要
cat > performance-summary.md << 'EOF'
# 性能巡检摘要 - $(date +%Y-%m-%d)

## 总体健康评分
$(jq '.results.summary.health_score' performance-result.json)

## 关键发现
$(jq -r '.results.issues.critical[] | "- **" + .severity + "**: " + .description' performance-result.json)

## 容量规划建议
$(jq -r '.results.capacity_planning.recommendations[] | "- " + .' performance-result.json)

## 趋势分析
$(jq -r '.results.trend_analysis.summary' performance-result.json)
EOF
```

## 预期结果

### 正常性能巡检结果

当系统性能状态良好时，预期输出如下特征：

```json
{
  "status": "success",
  "results": {
    "summary": {
      "health_score": 88.5,
      "overall_status": "healthy",
      "performance_score": 90.2,
      "bottlenecks_found": 0
    },
    "trend_analysis": {
      "performance_trends": {
        "cpu_usage": {
          "current": 45.2,
          "30d_avg": 42.8,
          "trend": "stable",
          "peak_usage": 78.5,
          "peak_time": "2026-02-02T14:30:00Z"
        },
        "memory_usage": {
          "current": 65.3,
          "30d_avg": 62.1,
          "trend": "slow_increase",
          "prediction_30d": 68.5
        }
      },
      "anomaly_detection": {
        "total_anomalies": 2,
        "severity": "low"
      }
    },
    "capacity_planning": {
      "current_utilization": {
        "cpu": "45.2%",
        "memory": "65.3%",
        "storage": "58.7%",
        "network": "42.1%"
      },
      "growth_rates": {
        "cpu": "0.5%/month",
        "memory": "1.2%/month",
        "storage": "2.5%/month"
      },
      "time_to_limit": {
        "cpu": ">12 months",
        "memory": "8 months",
        "storage": "5 months"
      },
      "recommendations": [
        "监控存储增长，计划6个月内扩容",
        "优化内存使用模式，延长升级周期"
      ]
    }
  }
}
```

### 性能问题巡检结果

当系统存在性能问题时，预期输出如下特征：

```json
{
  "status": "success",
  "results": {
    "summary": {
      "health_score": 62.3,
      "overall_status": "degraded",
      "performance_score": 55.8,
      "bottlenecks_found": 3
    },
    "bottleneck_analysis": {
      "primary_bottleneck": {
        "type": "disk_io",
        "severity": "critical",
        "metric": "await_time",
        "current_value": "125ms",
        "threshold": "20ms",
        "affected_components": ["/dev/sdb", "database_volume"]
      },
      "secondary_bottlenecks": [
        {
          "type": "memory_contention",
          "severity": "warning",
          "metric": "swap_usage",
          "current_value": "15%",
          "threshold": "5%"
        }
      ]
    },
    "root_cause_analysis": {
      "likely_causes": [
        {
          "cause": "数据库索引碎片化",
          "confidence": 0.85,
          "evidence": [
            "表扫描比例增加",
            "索引命中率下降",
            "IO等待时间增长"
          ]
        }
      ],
      "recommended_actions": [
        {
          "action": "重建数据库索引",
          "priority": "high",
          "estimated_impact": "减少60% IO等待",
          "risk": "medium",
          "duration": "2小时"
        }
      ]
    },
    "capacity_planning": {
      "urgent_actions": [
        "立即优化数据库索引",
        "增加IOPS容量（SSD升级）"
      ],
      "timeline": {
        "immediate": ["索引优化"],
        "1_week": ["监控优化效果"],
        "1_month": ["存储升级评估"],
        "3_months": ["完成存储升级"]
      }
    }
  }
}
```

## 性能指标解读指南

### CPU性能指标

| 指标 | 正常范围 | 警告阈值 | 严重阈值 | 含义 |
|------|----------|----------|----------|------|
| CPU使用率 | <70% | 70-85% | >85% | 总体CPU负载 |
| 负载平均值 | <CPU核心数 | 核心数×1.5 | 核心数×2.0 | 系统负载 |
| 用户态CPU | <60% | 60-75% | >75% | 应用CPU使用 |
| 系统态CPU | <20% | 20-30% | >30% | 内核CPU使用 |
| IO等待CPU | <5% | 5-10% | >10% | IO阻塞时间 |
| 软中断 | <10% | 10-20% | >20% | 中断处理负载 |

### 内存性能指标

| 指标 | 正常范围 | 警告阈值 | 严重阈值 | 含义 |
|------|----------|----------|----------|------|
| 内存使用率 | <70% | 70-85% | >85% | 物理内存使用 |
| 交换使用率 | <5% | 5-20% | >20% | 交换空间使用 |
| 页错误率 | <100/s | 100-500/s | >500/s | 缺页中断 |
| 缓存命中率 | >90% | 80-90% | <80% | 缓存效率 |
| 内存泄漏检测 | 无增长 | 缓慢增长 | 快速增长 | 内存泄漏 |

### 磁盘性能指标

| 指标 | 正常范围 | 警告阈值 | 严重阈值 | 含义 |
|------|----------|----------|----------|------|
| IOPS | 设备相关 | 80%容量 | 90%容量 | IO操作数 |
| 吞吐量 | 设备相关 | 80%带宽 | 90%带宽 | 数据传输率 |
| 响应时间 | <10ms | 10-50ms | >50ms | IO延迟 |
| 队列长度 | <2 | 2-5 | >5 | IO等待队列 |
| 使用率 | <80% | 80-90% | >90% | 磁盘空间 |

### 网络性能指标

| 指标 | 正常范围 | 警告阈值 | 严重阈值 | 含义 |
|------|----------|----------|----------|------|
| 带宽使用率 | <70% | 70-85% | >85% | 网络带宽 |
| 包错误率 | <0.1% | 0.1-1% | >1% | 网络质量 |
| 延迟 | <50ms | 50-100ms | >100ms | 网络延迟 |
| 连接数 | 系统相关 | 80%上限 | 90%上限 | 并发连接 |
| 重传率 | <1% | 1-5% | >5% | 网络稳定性 |

## 瓶颈分析方法

### 四步瓶颈分析流程

#### 步骤1：识别瓶颈类型
```bash
# 使用巡检结果识别瓶颈
jq '.results.bottleneck_analysis.primary_bottleneck' performance-result.json

# 手动验证瓶颈
# CPU瓶颈检查
mpstat -P ALL 2 5
pidstat -u 2 5

# 内存瓶颈检查
vmstat 2 5
pidstat -r 2 5

# 磁盘瓶颈检查
iostat -x 2 5
pidstat -d 2 5

# 网络瓶颈检查
sar -n DEV 2 5
ss -s
```

#### 步骤2：定位瓶颈源头
```bash
# 根据瓶颈类型定位具体进程/服务

# CPU高使用进程
ps aux --sort=-%cpu | head -10

# 内存高使用进程
ps aux --sort=-%mem | head -10

# 磁盘高IO进程
iotop -o -b -n 5

# 网络高流量进程
nethogs
```

#### 步骤3：分析瓶颈原因
```bash
# 深度分析具体进程

# Java应用分析
jstack <pid> > thread-dump.txt
jmap -histo <pid> > memory-histogram.txt

# 数据库分析
# 检查慢查询
# 检查锁等待
# 检查索引使用

# 应用日志分析
grep -E "(ERROR|WARN|slow|timeout)" /var/log/application.log
```

#### 步骤4：制定优化方案
基于分析结果制定优化方案：
1. **配置优化**：调整系统/应用参数
2. **代码优化**：修复性能问题代码
3. **架构优化**：调整系统架构
4. **硬件升级**：增加资源容量

## 容量规划方法

### 趋势预测模型

#### 线性增长预测
```python
# 基于历史数据的线性预测
import numpy as np
from datetime import datetime, timedelta

def predict_capacity_linear(historical_data, forecast_days):
    """线性预测容量需求"""
    dates = [d['date'] for d in historical_data]
    values = [d['value'] for d in historical_data]

    # 计算日增长率
    daily_growth = (values[-1] - values[0]) / len(values)

    # 预测未来值
    forecast = []
    for i in range(1, forecast_days + 1):
        forecast_date = datetime.now() + timedelta(days=i)
        forecast_value = values[-1] + daily_growth * i
        forecast.append({
            'date': forecast_date.strftime('%Y-%m-%d'),
            'value': forecast_value
        })

    return forecast
```

#### 季节性预测
```python
# 考虑季节性因素的预测
def predict_capacity_seasonal(historical_data, forecast_days):
    """季节性预测容量需求"""
    # 识别日/周/月模式
    # 使用时间序列分析方法
    # 考虑业务周期因素
    pass
```

### 容量规划报告模板

```markdown
# 容量规划报告 - $(date +%Y-%m-%d)

## 1. 当前资源使用情况
| 资源类型 | 当前使用 | 容量上限 | 使用率 | 状态 |
|----------|----------|----------|--------|------|
| CPU | 45.2% | 100% | 45.2% | 正常 |
| 内存 | 65.3% | 64GB | 65.3% | 正常 |
| 存储 | 58.7% | 1TB | 58.7% | 正常 |
| 网络 | 42.1% | 1Gbps | 42.1% | 正常 |

## 2. 增长趋势分析
| 资源类型 | 日增长率 | 月增长率 | 趋势 |
|----------|----------|----------|------|
| CPU | 0.02%/天 | 0.5%/月 | 稳定 |
| 内存 | 0.04%/天 | 1.2%/月 | 缓慢增长 |
| 存储 | 0.08%/天 | 2.5%/月 | 快速增长 |
| 网络 | 0.03%/天 | 0.9%/月 | 稳定 |

## 3. 容量预测
| 资源类型 | 30天预测 | 90天预测 | 180天预测 | 达到上限时间 |
|----------|----------|----------|-----------|--------------|
| CPU | 46.7% | 48.2% | 50.2% | >12个月 |
| 内存 | 68.5% | 72.1% | 77.5% | 8个月 |
| 存储 | 66.2% | 81.2% | 100% | 5个月 |

## 4. 建议措施
### 立即行动（<1个月）
- 监控存储增长趋势
- 优化存储使用（清理临时文件）

### 短期计划（1-3个月）
- 制定存储扩容方案
- 评估SSD升级可行性

### 中长期计划（3-12个月）
- 执行存储扩容
- 规划内存升级
```

## 故障排除

### 性能巡检常见问题

#### 问题1：历史数据不足
**症状**：趋势分析失败，缺少历史数据
**解决方法**：
```bash
# 检查metric-analyzer数据
claude witty-diagnosis:metric-analyzer --status
claude witty-diagnosis:metric-analyzer --query "cpu.usage" --days 7

# 临时解决方案：使用较短的分析周期
--trend-analysis-days 3
--parameters '{"performance_analysis": {"analysis_period": "12h"}}'
```

#### 问题2：性能数据采样不准确
**症状**：性能指标波动大，分析结果不稳定
**解决方法**：
```bash
# 增加采样频率和时长
--parameters '{
  "performance_analysis": {
    "sampling_interval": 1,
    "sampling_duration": 300
  }
}'

# 使用统计方法平滑数据
--parameters '{
  "performance_analysis": {
    "use_statistical_smoothing": true,
    "smoothing_window": 5
  }
}'
```

#### 问题3：应用性能数据缺失
**症状**：应用层性能指标不可用
**解决方法**：
```bash
# 启用应用性能监控
--parameters '{
  "performance_analysis": {
    "include_application_performance": true,
    "application_metrics": [
      "response_time",
      "throughput",
      "error_rate"
    ]
  }
}'

# 集成APM工具
# 配置应用性能监控代理
# 设置性能数据导出
```

### 性能优化验证

#### A/B测试方法
```bash
#!/bin/bash
# 性能优化A/B测试脚本

# 优化前基准测试
claude witty-diagnosis:intelligent-inspection \
  --session-id "performance-baseline-$(date +%Y%m%d)" \
  --inspection-type performance \
  --output-file baseline.json

# 执行优化操作
echo "执行性能优化..."
# ... 优化操作 ...

# 优化后测试
claude witty-diagnosis:intelligent-inspection \
  --session-id "performance-optimized-$(date +%Y%m%d)" \
  --inspection-type performance \
  --output-file optimized.json

# 对比结果
baseline_score=$(jq '.results.summary.performance_score' baseline.json)
optimized_score=$(jq '.results.summary.performance_score' optimized.json)
improvement=$(echo "scale=2; ($optimized_score - $baseline_score) / $baseline_score * 100" | bc)

echo "优化效果: $improvement% 提升"
echo "基准分数: $baseline_score"
echo "优化后分数: $optimized_score"
```

#### 持续监控方法
```bash
#!/bin/bash
# 性能优化持续监控脚本

# 设置监控周期
monitor_days=7
check_interval=3600  # 1小时

for ((i=0; i<monitor_days*24; i++)); do
  timestamp=$(date +%Y%m%d-%H%M)

  # 执行性能检查
  claude witty-diagnosis:intelligent-inspection \
    --session-id "performance-monitor-$timestamp" \
    --inspection-type performance \
    --inspection-depth quick \
    --output-file "monitor-$timestamp.json"

  # 记录关键指标
  health_score=$(jq '.results.summary.health_score' "monitor-$timestamp.json")
  performance_score=$(jq '.results.summary.performance_score' "monitor-$timestamp.json")

  echo "$timestamp, $health_score, $performance_score" >> performance-trend.csv

  # 等待下一个检查点
  sleep $check_interval
done

# 生成趋势图表
gnuplot << EOF
set datafile separator ","
set terminal png size 1200,600
set output "performance-trend.png"
set xdata time
set timefmt "%Y%m%d-%H%M"
set format x "%m/%d %H:%M"
set xlabel "时间"
set ylabel "评分"
set title "性能优化监控趋势"
plot "performance-trend.csv" using 1:2 with lines title "健康评分", \
     "performance-trend.csv" using 1:3 with lines title "性能评分"
EOF
```

## 最佳实践

### 性能巡检计划

#### 巡检频率建议
- **实时监控**：关键指标持续监控
- **小时检查**：性能趋势快速检查
- **日度检查**：性能健康日常检查
- **周度深度检查**：瓶颈分析和趋势预测
- **月度全面检查**：容量规划和优化评估

#### 业务场景对应
- **业务高峰前**：容量验证和压力测试
- **版本发布后**：性能回归测试
- **故障恢复后**：性能稳定性验证
- **架构变更后**：性能影响评估

### 性能基线管理

#### 建立性能基线
```bash
# 在系统健康状态下建立基线
claude witty-diagnosis:intelligent-inspection \
  --session-id "performance-baseline-establish" \
  --inspection-type performance \
  --inspection-depth deep \
  --trend-analysis-days 7 \
  --parameters '{
    "save_as_baseline": true,
    "baseline_name": "healthy-state-2026-Q1"
  }'
```

#### 基线比较和告警
```bash
#!/bin/bash
# 基线比较和告警脚本

# 执行当前检查
current_result=$(claude witty-diagnosis:intelligent-inspection \
  --session-id "performance-check-$(date +%Y%m%d)" \
  --inspection-type performance \
  --inspection-depth standard)

# 加载基线
baseline=$(cat /etc/witty-diagnosis/baselines/healthy-state-2026-Q1.json)

# 比较关键指标
current_score=$(echo "$current_result" | jq '.results.summary.performance_score')
baseline_score=$(echo "$baseline" | jq '.results.summary.performance_score')

threshold=10  # 10%偏差阈值
deviation=$(echo "scale=2; ($current_score - $baseline_score) / $baseline_score * 100" | bc | tr -d '-')

if (( $(echo "$deviation > $threshold" | bc -l) )); then
  send_alert "性能偏差告警" "当前性能评分偏差 $deviation%，超过阈值 $threshold%"
fi
```

### 性能优化工作流

#### 优化迭代流程
1. **发现问题**：通过巡检识别性能问题
2. **分析根因**：深入分析问题原因
3. **制定方案**：设计优化解决方案
4. **实施优化**：执行优化措施
5. **验证效果**：验证优化效果
6. **监控持续**：持续监控防止回退

#### 优化优先级矩阵
| 问题严重度 | 优化难度 | 优化收益 | 优先级 |
|------------|----------|----------|--------|
| 高 | 低 | 高 | P0（立即） |
| 高 | 高 | 高 | P1（短期） |
| 中 | 低 | 高 | P1（短期） |
| 高 | 高 | 中 | P2（中期） |
| 中 | 中 | 中 | P2（中期） |
| 低 | 低 | 高 | P3（长期） |

## 扩展场景

### 场景1：分布式系统性能巡检

```bash
#!/bin/bash
# 分布式系统性能巡检脚本

nodes=("web-01" "web-02" "app-01" "app-02" "db-01" "cache-01")

# 并行执行各节点巡检
for node in "${nodes[@]}"; do
  (
    echo "开始检查节点: $node"
    ssh "$node" "claude witty-diagnosis:intelligent-inspection \
      --session-id \"cluster-perf-$node-$(date +%Y%m%d)\" \
      --inspection-type performance \
      --inspection-depth standard \
      --output-file /tmp/perf-$node.json"

    # 收集结果
    scp "$node:/tmp/perf-$node.json" "results/perf-$node.json"
  ) &
done

wait

# 聚合分析
echo "所有节点检查完成，开始聚合分析..."

# 计算集群整体健康评分
total_score=0
node_count=0
for node in "${nodes[@]}"; do
  score=$(jq '.results.summary.health_score' "results/perf-$node.json")
  total_score=$(echo "$total_score + $score" | bc)
  node_count=$((node_count + 1))
done

average_score=$(echo "scale=2; $total_score / $node_count" | bc)
echo "集群平均健康评分: $average_score"

# 识别瓶颈节点
for node in "${nodes[@]}"; do
  score=$(jq '.results.summary.health_score' "results/perf-$node.json")
  if (( $(echo "$score < 70" | bc -l) )); then
    echo "警告: 节点 $node 健康评分过低: $score"
  fi
done
```

### 场景2：云环境性能巡检

```bash
#!/bin/bash
# 云环境性能巡检脚本

# 获取云实例列表
instances=$(aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=production" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)

for instance in $instances; do
  echo "检查云实例: $instance"

  # 获取实例信息
  instance_info=$(aws ec2 describe-instances --instance-ids "$instance")
  instance_type=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].InstanceType')
  private_ip=$(echo "$instance_info" | jq -r '.Reservations[0].Instances[0].PrivateIpAddress')

  # 通过SSH执行巡检
  ssh "ec2-user@$private_ip" "claude witty-diagnosis:intelligent-inspection \
    --session-id \"cloud-instance-$instance-$(date +%Y%m%d)\" \
    --inspection-type performance \
    --parameters '{
      \"cloud_context\": {
        \"instance_type\": \"$instance_type\",
        \"instance_id\": \"$instance\",
        \"provider\": \"aws\"
      }
    }'"

  # 收集云监控指标
  cloud_metrics=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=InstanceId,Value="$instance" \
    --start-time "$(date -d '1 hour ago' --iso-8601=seconds)" \
    --end-time "$(date --iso-8601=seconds)" \
    --period 300 \
    --statistics Average)

  echo "云监控指标: $cloud_metrics"
done
```

### 场景3：容器化应用性能巡检

```bash
#!/bin/bash
# 容器化应用性能巡检脚本

# 检查Kubernetes集群节点
kubectl get nodes -o wide

# 检查Pod资源使用
kubectl top pods --all-namespaces

# 对每个应用执行性能巡检
applications=("frontend" "backend" "database" "cache")

for app in "${applications[@]}"; do
  echo "检查应用: $app"

  # 获取应用Pod
  pod=$(kubectl get pods -l app="$app" -o jsonpath='{.items[0].metadata.name}')

  # 在Pod内执行性能检查
  kubectl exec "$pod" -- claude witty-diagnosis:intelligent-inspection \
    --session-id "container-app-$app-$(date +%Y%m%d)" \
    --inspection-type performance \
    --parameters '{
      "container_context": {
        "runtime": "docker",
        "orchestrator": "kubernetes",
        "namespace": "production"
      }
    }'

  # 收集容器指标
  container_metrics=$(kubectl describe pod "$pod" | grep -A5 "Limits\|Requests")
  echo "容器资源限制: $container_metrics"
done
```

---

*示例版本：1.0.0*
*最后更新：2026-02-03*