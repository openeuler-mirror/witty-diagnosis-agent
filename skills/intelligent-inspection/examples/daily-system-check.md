# 日常系统检查示例

## 场景描述

本示例展示如何使用intelligent-inspection技能进行日常系统健康检查。日常检查是运维工作中的基础环节，旨在快速发现系统潜在问题，确保系统稳定运行。

**适用场景**：
- 每日早晨的系统健康检查
- 系统变更后的验证检查
- 业务高峰前的预防性检查
- 周期性维护前的状态评估

**检查重点**：
1. 系统资源使用情况（CPU、内存、磁盘）
2. 关键服务运行状态
3. 系统负载和性能趋势
4. 安全配置基础检查
5. 网络连通性检查

## 前置条件

### 系统要求
- 欧拉OS 2.0或更高版本
- 至少2GB可用内存
- 至少100MB磁盘空间用于临时文件
- 网络连接正常

### 配置要求
- data-collector技能已安装并配置
- metric-analyzer技能已安装并配置
- intelligent-inspection技能已安装
- 执行用户具有适当的系统权限

### 数据准备
- 确保系统正常运行至少24小时，以便进行趋势分析
- 确认knowledge-base中有可用的基线数据
- 准备检查目标系统的访问凭证（如需要）

## 执行步骤

### 步骤1：准备巡检配置

创建巡检配置文件 `daily-check-config.json`：

```json
{
  "session_id": "daily-system-check-20260203",
  "inspection_type": "daily",
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    "inspection_depth": "standard",
    "check_categories": [
      "system",
      "performance",
      "security",
      "storage",
      "network"
    ],
    "alert_threshold": {
      "critical": 90,
      "warning": 80,
      "info": 60
    },
    "trend_analysis_days": 7,
    "generate_report": true,
    "send_alerts": false,
    "compare_with_baseline": true,
    "output_format": "json"
  },
  "metadata": {
    "request_id": "daily-check-001",
    "timestamp": "2026-02-03T08:00:00Z",
    "environment": "production",
    "scheduled": true,
    "schedule_name": "daily-morning-check",
    "operator": "system-admin",
    "purpose": "routine_health_check"
  }
}
```

### 步骤2：执行巡检命令

使用命令行工具执行巡检：

```bash
# 方式1：直接使用命令行参数
claude witty-diagnosis:intelligent-inspection \
  --session-id "daily-system-check-20260203" \
  --inspection-type daily \
  --inspection-depth standard \
  --check-categories system performance security storage network \
  --timeout 300 \
  --generate-report \
  --output-format json

# 方式2：使用配置文件
claude witty-diagnosis:intelligent-inspection --config-file daily-check-config.json

# 方式3：通过API调用
curl -X POST http://localhost:8080/api/v1/inspection \
  -H "Content-Type: application/json" \
  -d @daily-check-config.json
```

### 步骤3：监控执行过程

巡检执行过程中可以监控以下指标：

```bash
# 查看执行日志
tail -f /var/log/witty-diagnosis/intelligent-inspection.log

# 监控资源使用
watch -n 5 "ps aux | grep intelligent-inspection"

# 检查临时文件
ls -la /tmp/witty-diagnosis/inspection-daily-system-check-20260203/
```

### 步骤4：分析巡检结果

巡检完成后，分析输出结果：

```bash
# 保存巡检结果
claude witty-diagnosis:intelligent-inspection --config-file daily-check-config.json > daily-check-result.json

# 提取关键信息
jq '.results.summary' daily-check-result.json
jq '.results.health_score_breakdown' daily-check-result.json
jq '.results.issues.critical[]?.description' daily-check-result.json
jq '.results.issues.warning[]?.description' daily-check-result.json
```

## 预期结果

### 成功巡检结果

当系统健康状态良好时，预期输出如下特征：

```json
{
  "status": "success",
  "results": {
    "summary": {
      "health_score": 85.0,
      "overall_status": "healthy",
      "total_checks": 120,
      "passed_checks": 115,
      "failed_checks": 2,
      "warning_checks": 3
    },
    "health_score_breakdown": {
      "system": 90.0,
      "performance": 85.0,
      "security": 95.0,
      "storage": 80.0,
      "network": 88.0
    },
    "issues": {
      "critical": [],
      "warning": [
        {
          "description": "磁盘使用率接近警告阈值",
          "severity": "warning",
          "current_value": 78.5
        }
      ],
      "info": [
        {
          "description": "SSH协议版本1仍被启用",
          "severity": "info"
        }
      ]
    }
  }
}
```

### 异常巡检结果

当系统存在问题时，预期输出如下特征：

```json
{
  "status": "success",
  "results": {
    "summary": {
      "health_score": 65.0,
      "overall_status": "degraded",
      "total_checks": 120,
      "passed_checks": 100,
      "failed_checks": 15,
      "warning_checks": 5
    },
    "issues": {
      "critical": [
        {
          "description": "根分区磁盘使用率超过95%",
          "severity": "critical",
          "recommendation": "立即清理磁盘空间"
        }
      ],
      "warning": [
        {
          "description": "内存使用率持续上升趋势",
          "severity": "warning",
          "trend": "increasing"
        }
      ]
    }
  }
}
```

## 结果解读指南

### 健康评分解读

| 评分范围 | 状态 | 含义 | 建议行动 |
|---------|------|------|----------|
| 90-100 | 优秀 | 系统状态极佳 | 继续保持当前运维策略 |
| 80-89 | 良好 | 系统状态良好 | 关注警告项，定期检查 |
| 70-79 | 一般 | 系统状态一般 | 需要优化，制定改进计划 |
| 60-69 | 警告 | 系统存在风险 | 立即处理警告项，监控关键指标 |
| 0-59 | 危险 | 系统严重问题 | 立即处理，可能影响业务 |

### 问题严重程度解读

#### 严重（Critical）
- **特征**：红色标识，评分影响大
- **影响**：可能立即导致服务中断或数据丢失
- **处理时限**：立即处理（<1小时）
- **示例**：磁盘空间不足、关键服务宕机、安全漏洞

#### 警告（Warning）
- **特征**：黄色标识，评分影响中等
- **影响**：可能在未来导致问题
- **处理时限**：24小时内处理
- **示例**：资源使用率接近阈值、配置不当、性能下降趋势

#### 信息（Info）
- **特征**：蓝色标识，评分影响小
- **影响**：不影响当前运行，建议优化
- **处理时限**：计划内处理
- **示例**：非关键配置优化、最佳实践建议、信息性提示

## 故障排除

### 常见问题及解决方法

#### 问题1：巡检执行时间过长
**症状**：巡检超过300秒仍未完成
**可能原因**：
- 系统负载过高
- 数据收集缓慢
- 网络延迟
- 配置问题

**解决方法**：
```bash
# 检查系统负载
uptime
top -bn1 | head -5

# 调整巡检配置
# 减少检查类别
--check-categories system performance

# 降低巡检深度
--inspection-depth quick

# 增加超时时间
--timeout 600
```

#### 问题2：依赖技能不可用
**症状**：错误信息显示依赖技能失败
**可能原因**：
- data-collector未运行
- 权限不足
- 网络问题

**解决方法**：
```bash
# 检查依赖技能状态
claude witty-diagnosis:data-collector --version
claude witty-diagnosis:metric-analyzer --status

# 重启依赖技能
systemctl restart witty-diagnosis-data-collector

# 使用简化模式（不依赖其他技能）
--inspection-depth quick --check-categories system
```

#### 问题3：权限不足
**症状**：部分检查失败，权限错误
**可能原因**：
- 执行用户权限不足
- SELinux限制
- 文件系统权限

**解决方法**：
```bash
# 检查当前用户权限
id
sudo -l

# 使用特权用户执行
sudo claude witty-diagnosis:intelligent-inspection ...

# 或配置sudo权限
# 在/etc/sudoers中添加：
# witty-user ALL=(ALL) NOPASSWD: /usr/bin/claude witty-diagnosis:intelligent-inspection *
```

#### 问题4：输出结果不完整
**症状**：部分检查类别缺失数据
**可能原因**：
- 检查类别配置错误
- 数据收集失败
- 输出格式问题

**解决方法**：
```bash
# 验证检查类别配置
jq '.parameters.check_categories' daily-check-config.json

# 检查详细日志
grep "ERROR\|WARN" /var/log/witty-diagnosis/intelligent-inspection.log

# 尝试简化输出格式
--output-format text
```

### 调试技巧

#### 启用详细日志
```bash
# 修改配置文件增加日志级别
{
  "parameters": {
    "verbosity": "debug"
  }
}

# 或使用命令行参数
--verbosity debug
```

#### 分步执行检查
```bash
# 先执行系统检查
claude witty-diagnosis:intelligent-inspection \
  --check-categories system \
  --inspection-depth quick

# 再执行性能检查
claude witty-diagnosis:intelligent-inspection \
  --check-categories performance \
  --inspection-depth standard
```

#### 保存中间结果
```bash
# 保存详细结果到文件
claude witty-diagnosis:intelligent-inspection \
  --config-file daily-check-config.json \
  --save-intermediate-results \
  --output-file /tmp/inspection-detailed.json
```

## 最佳实践

### 巡检计划安排

#### 时间安排建议
- **每日检查**：业务开始前1小时（如08:00）
- **每周深度检查**：周末业务低峰期
- **月度全面检查**：月度维护窗口

#### 资源考虑
- 避免在业务高峰期执行深度巡检
- 考虑系统备份时间窗口
- 避开系统更新和维护时段

### 配置优化建议

#### 生产环境配置
```json
{
  "parameters": {
    "timeout": 600,
    "inspection_depth": "standard",
    "alert_threshold": {
      "critical": 90,
      "warning": 80,
      "info": 70
    },
    "generate_report": true,
    "compare_with_baseline": true
  }
}
```

#### 开发/测试环境配置
```json
{
  "parameters": {
    "timeout": 300,
    "inspection_depth": "quick",
    "alert_threshold": {
      "critical": 95,
      "warning": 85
    },
    "generate_report": false
  }
}
```

### 结果处理流程

#### 自动化处理流程
```bash
#!/bin/bash
# 日常巡检自动化脚本

# 1. 执行巡检
result=$(claude witty-diagnosis:intelligent-inspection \
  --session-id "daily-check-$(date +%Y%m%d)" \
  --inspection-type daily \
  --output-format json)

# 2. 解析结果
health_score=$(echo "$result" | jq '.results.summary.health_score')
critical_issues=$(echo "$result" | jq '.results.issues.critical | length')

# 3. 判断处理
if [ "$health_score" -lt 60 ] || [ "$critical_issues" -gt 0 ]; then
  # 发送告警
  send_alert "系统健康检查失败" "$result"
  # 记录到问题跟踪系统
  log_to_ticket_system "$result"
fi

# 4. 保存结果
echo "$result" > "/var/log/witty-diagnosis/daily-check-$(date +%Y%m%d).json"
```

#### 人工审查流程
1. **每日审查**：运维人员审查健康评分和严重问题
2. **每周审查**：团队审查趋势分析和改进建议
3. **月度审查**：管理层审查系统健康趋势和容量规划

### 集成建议

#### 与监控系统集成
```bash
# 将巡检结果推送到监控系统
curl -X POST http://monitoring-system/api/metrics \
  -H "Content-Type: application/json" \
  -d "{
    \"metric\": \"system.health_score\",
    \"value\": $health_score,
    \"timestamp\": \"$(date -Iseconds)\"
  }"
```

#### 与告警系统集成
```bash
# 根据巡检结果触发告警
if jq -e '.results.issues.critical | length > 0' daily-check-result.json; then
  send_slack_alert "发现严重问题" "$(jq '.results.issues.critical' daily-check-result.json)"
fi
```

#### 与知识库集成
```bash
# 保存巡检结果到知识库
claude witty-diagnosis:knowledge-base \
  --operation store \
  --data-type inspection_result \
  --data-file daily-check-result.json \
  --tags "daily-check,production,$(date +%Y-%m-%d)"
```

## 扩展场景

### 场景1：多节点批量巡检

```bash
#!/bin/bash
# 多节点批量巡检脚本

nodes=("node1.example.com" "node2.example.com" "node3.example.com")

for node in "${nodes[@]}"; do
  echo "检查节点: $node"

  # 通过SSH远程执行
  ssh "admin@$node" "claude witty-diagnosis:intelligent-inspection \
    --session-id \"daily-check-$node-$(date +%Y%m%d)\" \
    --inspection-type daily \
    --output-format json" > "result-$node.json"

  # 汇总结果
  health_score=$(jq '.results.summary.health_score' "result-$node.json")
  echo "节点 $node 健康评分: $health_score"
done
```

### 场景2：变更前后对比

```bash
#!/bin/bash
# 变更验证脚本

# 变更前巡检
claude witty-diagnosis:intelligent-inspection \
  --session-id "pre-change-$(date +%Y%m%d-%H%M)" \
  --inspection-type daily \
  --output-file pre-change.json

# 执行变更操作
# ... 执行系统变更 ...

# 变更后巡检
claude witty-diagnosis:intelligent-inspection \
  --session-id "post-change-$(date +%Y%m%d-%H%M)" \
  --inspection-type daily \
  --output-file post-change.json

# 对比结果
diff -u <(jq '.' pre-change.json) <(jq '.' post-change.json) > change-diff.txt
```

### 场景3：趋势监控仪表板

```python
#!/usr/bin/env python3
# 趋势监控脚本

import json
import matplotlib.pyplot as plt
from datetime import datetime, timedelta

# 加载最近7天的巡检结果
results = []
for i in range(7):
    date = (datetime.now() - timedelta(days=i)).strftime('%Y%m%d')
    try:
        with open(f'/var/log/witty-diagnosis/daily-check-{date}.json') as f:
            data = json.load(f)
            results.append({
                'date': date,
                'health_score': data['results']['summary']['health_score'],
                'issues': len(data['results']['issues']['critical']) +
                         len(data['results']['issues']['warning'])
            })
    except FileNotFoundError:
        continue

# 生成趋势图表
dates = [r['date'] for r in results]
scores = [r['health_score'] for r in results]
issues = [r['issues'] for r in results]

plt.figure(figsize=(10, 6))
plt.plot(dates, scores, 'b-', label='健康评分')
plt.plot(dates, issues, 'r-', label='问题数量')
plt.xlabel('日期')
plt.ylabel('数值')
plt.title('系统健康趋势')
plt.legend()
plt.grid(True)
plt.savefig('/var/www/html/health-trend.png')
```

---

*示例版本：1.0.0*
*最后更新：2026-02-03*