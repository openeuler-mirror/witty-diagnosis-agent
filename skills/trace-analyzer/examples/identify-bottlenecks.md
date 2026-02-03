# 瓶颈识别示例

## 场景描述

在一个在线支付系统中，用户报告支付处理时间从正常的200-300ms增加到1500ms以上。系统处理支付的完整流程涉及多个微服务：

```
支付请求流程：
1. gateway-service → 接收支付请求
2. auth-service → 验证用户身份和权限
3. payment-service → 处理支付逻辑
4. fraud-detection-service → 欺诈检测
5. bank-gateway-service → 与银行系统通信
6. notification-service → 发送支付结果通知
```

系统架构特点：
- 高并发：峰值时每秒处理1000+支付请求
- 关键业务：支付成功率直接影响用户体验和收入
- 复杂依赖：涉及外部银行系统和第三方服务

## 前置条件

### 系统状态
- 支付系统已运行6个月，有稳定的性能基线
- 最近一周观察到支付处理时间逐渐增加
- 错误率从0.1%上升到1.5%
- 系统负载正常，资源使用率在合理范围内

### 数据收集
已收集以下时间段的追踪数据：
1. **正常时期**：2026-01-25 至 2026-01-31（性能基线）
2. **异常时期**：2026-02-01 至 2026-02-03（问题时期）
3. **对比数据**：相同业务量下的追踪数据样本

### 追踪数据特征
- 数据格式：Jaeger JSON格式
- 时间范围：24小时连续数据
- 数据量：约50,000个trace，包含300,000个span
- 关键标签：包含支付金额、支付方式、用户等级等信息

## 执行步骤

### 步骤1：准备分析数据

创建包含支付处理链路的追踪数据文件：

```json
// payment-trace-sample.json
[
  {
    "traceId": "payment-trace-001",
    "spanId": "span-gateway",
    "parentSpanId": null,
    "operationName": "POST /api/v1/payments",
    "startTime": "2026-02-03T14:30:00.123Z",
    "duration": 1580,
    "tags": {
      "http.method": "POST",
      "http.status_code": 200,
      "service.name": "gateway-service",
      "payment.amount": "199.99",
      "payment.currency": "USD",
      "payment.method": "credit_card",
      "user.tier": "premium"
    },
    "logs": [
      {
        "timestamp": "2026-02-03T14:30:00.123Z",
        "fields": {"event": "payment_request_received"}
      }
    ]
  },
  {
    "traceId": "payment-trace-001",
    "spanId": "span-auth",
    "parentSpanId": "span-gateway",
    "operationName": "Validate Payment Authorization",
    "startTime": "2026-02-03T14:30:00.178Z",
    "duration": 85,
    "tags": {
      "service.name": "auth-service",
      "auth.result": "success",
      "user.balance": "1500.00",
      "credit.limit": "5000.00"
    }
  },
  {
    "traceId": "payment-trace-001",
    "spanId": "span-payment",
    "parentSpanId": "span-auth",
    "operationName": "Process Payment",
    "startTime": "2026-02-03T14:30:00.263Z",
    "duration": 1250,
    "tags": {
      "service.name": "payment-service",
      "payment.status": "processing",
      "transaction.id": "txn-789012",
      "retry.count": 0
    },
    "logs": [
      {
        "timestamp": "2026-02-03T14:30:00.263Z",
        "fields": {"event": "payment_processing_started"}
      },
      {
        "timestamp": "2026-02-03T14:30:01.513Z",
        "fields": {"event": "payment_processing_completed"}
      }
    ]
  },
  {
    "traceId": "payment-trace-001",
    "spanId": "span-fraud",
    "parentSpanId": "span-payment",
    "operationName": "Fraud Detection Check",
    "startTime": "2026-02-03T14:30:00.313Z",
    "duration": 420,
    "tags": {
      "service.name": "fraud-detection-service",
      "fraud.score": "12",
      "risk.level": "low",
      "check.type": "realtime"
    }
  },
  {
    "traceId": "payment-trace-001",
    "spanId": "span-bank",
    "parentSpanId": "span-payment",
    "operationName": "Bank Transaction",
    "startTime": "2026-02-03T14:30:00.833Z",
    "duration": 800,
    "tags": {
      "service.name": "bank-gateway-service",
      "bank.name": "example-bank",
      "transaction.status": "success",
      "response.time": 780
    }
  },
  {
    "traceId": "payment-trace-001",
    "spanId": "span-notify",
    "parentSpanId": "span-payment",
    "operationName": "Send Payment Notification",
    "startTime": "2026-02-03T14:30:01.633Z",
    "duration": 30,
    "tags": {
      "service.name": "notification-service",
      "notification.type": "payment_success",
      "channel": "email",
      "status": "sent"
    }
  }
]
```

### 步骤2：执行瓶颈分析

使用trace-analyzer进行深度瓶颈分析：

```bash
# 深度性能瓶颈分析
claude witty-diagnosis:trace-analyzer \
  --session-id "payment-bottleneck-deep-001" \
  --trace-data payment-trace-sample.json \
  --analysis-type latency \
  --latency-threshold-ms 200 \
  --time-window-start "2026-02-03T14:00:00Z" \
  --time-window-end "2026-02-03T15:00:00Z" \
  --output-format json \
  --verbosity debug
```

### 步骤3：对比历史基线

与历史正常时期数据进行对比分析：

```bash
# 对比分析：异常时期 vs 正常时期
claude witty-diagnosis:trace-analyzer \
  --session-id "payment-comparison-001" \
  --trace-data payment-trace-current.json \
  --baseline-data payment-trace-baseline.json \
  --analysis-type comparison \
  --comparison-metrics "latency,error_rate,throughput" \
  --output-format json
```

### 步骤4：模式识别分析

识别特定模式下的瓶颈：

```bash
# 按支付金额分组的瓶颈分析
claude witty-diagnosis:trace-analyzer \
  --session-id "payment-pattern-001" \
  --trace-data payment-trace-sample.json \
  --analysis-type pattern \
  --group-by "payment.amount_range,payment.method,user.tier" \
  --pattern-types "slow_queries,timeouts,retries" \
  --output-format json
```

### 步骤5：根因定位分析

定位瓶颈的根本原因：

```bash
# 根因定位分析
claude witty-diagnosis:trace-analyzer \
  --session-id "payment-root-cause-001" \
  --trace-data payment-trace-sample.json \
  --analysis-type root-cause \
  --root-cause-methods "correlation,propagation,impact" \
  --confidence-threshold 0.75 \
  --output-format json
```

## 预期结果

### 瓶颈识别结果

分析应识别以下瓶颈：

#### 1. 主要瓶颈（高影响）
```json
{
  "bottleneck_id": "bottleneck-001",
  "service_name": "payment-service",
  "operation_name": "Process Payment",
  "metrics": {
    "avg_latency_ms": 1250,
    "p95_latency_ms": 1850,
    "p99_latency_ms": 2450,
    "contribution_percent": 79.1,
    "call_count": 50000,
    "error_rate_percent": 1.2,
    "timeout_rate_percent": 0.8
  },
  "characteristics": {
    "type": "processing_delay",
    "severity": "critical",
    "trend": "increasing",
    "pattern": "consistent_high_latency"
  }
}
```

#### 2. 次要瓶颈（中影响）
```json
{
  "bottleneck_id": "bottleneck-002",
  "service_name": "bank-gateway-service",
  "operation_name": "Bank Transaction",
  "metrics": {
    "avg_latency_ms": 800,
    "p95_latency_ms": 1250,
    "contribution_percent": 50.6,
    "variability": "high",
    "external_dependency": true
  }
}
```

#### 3. 潜在瓶颈（低影响）
```json
{
  "bottleneck_id": "bottleneck-003",
  "service_name": "fraud-detection-service",
  "operation_name": "Fraud Detection Check",
  "metrics": {
    "avg_latency_ms": 420,
    "p95_latency_ms": 680,
    "contribution_percent": 26.6,
    "trend": "stable"
  }
}
```

### 瓶颈特征分析

#### 时间特征
- **周期性**：每天14:00-16:00延迟最高（银行系统高峰）
- **趋势性**：过去一周延迟每天增加约10%
- **突发性**：偶尔出现3000ms+的极端延迟

#### 业务特征
- **金额相关**：大额支付（>1000USD）延迟增加更明显
- **用户相关**：新用户支付延迟高于老用户
- **支付方式**：信用卡支付延迟高于其他方式

#### 系统特征
- **资源相关**：payment-service CPU使用率与延迟正相关
- **依赖相关**：bank-gateway响应时间波动大
- **容量相关**：并发请求数超过1000时延迟显著增加

### 根因分析结果

#### 主要根因
```json
{
  "root_cause_id": "rc-001",
  "type": "database_contention",
  "service": "payment-service",
  "confidence": 0.88,
  "evidence": [
    "payment-service数据库连接池使用率95%",
    "支付记录表索引碎片化严重",
    "同一时段大量支付请求竞争数据库资源",
    "慢查询日志显示支付状态更新语句执行时间长"
  ],
  "impact": {
    "affected_services": ["payment-service", "gateway-service", "auth-service"],
    "user_impact": "所有支付用户",
    "business_impact": "支付成功率下降2%"
  }
}
```

#### 次要根因
```json
{
  "root_cause_id": "rc-002",
  "type": "external_dependency",
  "service": "bank-gateway-service",
  "confidence": 0.72,
  "evidence": [
    "银行API响应时间波动大（200ms-1500ms）",
    "银行系统维护时段延迟增加",
    "第三方服务SLA不达标"
  ]
}
```

## 优化建议

### 立即执行（24小时内）

#### 1. 数据库优化
```bash
# 优化支付记录表
ALTER TABLE payment_transactions
REBUILD INDEX idx_payment_status;

# 调整连接池配置
UPDATE service_config
SET connection_pool_size = 50
WHERE service_name = 'payment-service';

# 添加查询缓存
ADD CACHE FOR payment_status_queries
WITH TTL 300 SECONDS;
```

#### 2. 服务配置调整
```yaml
# payment-service配置优化
payment:
  processing:
    timeout: 3000  # 增加超时时间
    retry:
      max_attempts: 3
      backoff: exponential
  database:
    connection_pool:
      max_size: 50
      min_idle: 10
    query:
      timeout: 2000
```

### 短期优化（1周内）

#### 1. 架构优化
- 实现支付处理异步化
- 引入消息队列解耦服务
- 添加支付结果缓存层

#### 2. 监控增强
- 设置关键路径SLA监控
- 实现自动瓶颈检测告警
- 建立性能基线自动更新机制

### 长期优化（1个月内）

#### 1. 系统重构
- 拆分payment-service为更细粒度服务
- 实现数据库读写分离
- 引入支付路由和负载均衡

#### 2. 容量规划
- 基于业务增长预测扩容需求
- 设计弹性伸缩方案
- 建立多区域部署架构

## 验证方法

### 性能测试验证

#### 1. 负载测试
```bash
# 执行负载测试脚本
./run_load_test.sh \
  --concurrent-users 1000 \
  --duration 30m \
  --endpoint "/api/v1/payments" \
  --data payment_requests.json

# 收集测试期间的追踪数据
collect_traces --test-id "load-test-001" --output load-test-traces.json

# 分析测试结果
claude witty-diagnosis:trace-analyzer \
  --trace-data load-test-traces.json \
  --analysis-type latency \
  --session-id "load-test-analysis-001"
```

#### 2. A/B测试验证
```bash
# 部署优化版本（B版本）
deploy_service --version "payment-service-optimized" --percentage 50

# 收集A/B版本对比数据
collect_ab_traces \
  --version-a "original" \
  --version-b "optimized" \
  --duration 2h \
  --output ab_traces.json

# 对比分析
claude witty-diagnosis:trace-analyzer \
  --trace-data ab_traces.json \
  --analysis-type comparison \
  --group-by "service_version" \
  --session-id "ab-test-analysis-001"
```

### 业务指标验证

#### 1. 关键业务指标
- 支付成功率：目标 > 99.5%
- 平均处理时间：目标 < 500ms
- P95处理时间：目标 < 1000ms
- 错误率：目标 < 0.5%

#### 2. 用户满意度指标
- 支付放弃率：目标 < 2%
- 用户投诉率：目标 < 0.1%
- NPS评分：目标 > 40

## 故障排除指南

### 瓶颈复现步骤

#### 步骤1：模拟瓶颈场景
```bash
# 生成模拟支付请求
generate_payment_requests \
  --count 10000 \
  --concurrency 200 \
  --amount-range "100-5000" \
  --output simulated_requests.json

# 重放请求
replay_requests \
  --input simulated_requests.json \
  --rate 100 \
  --duration 10m
```

#### 步骤2：监控瓶颈指标
```bash
# 实时监控关键指标
monitor_metrics \
  --services "payment-service,bank-gateway-service" \
  --metrics "latency_p95,error_rate,cpu_usage,db_connections" \
  --interval 5s \
  --duration 15m
```

#### 步骤3：分析瓶颈特征
```bash
# 收集瓶颈期间的追踪数据
collect_traces_during_bottleneck \
  --trigger-metric "payment_service_latency_p95" \
  --threshold 1000 \
  --duration 5m \
  --output bottleneck_traces.json

# 深度分析
claude witty-diagnosis:trace-analyzer \
  --trace-data bottleneck_traces.json \
  --analysis-type comprehensive \
  --session-id "bottleneck-debug-001"
```

### 常见瓶颈模式及解决方案

#### 模式1：数据库连接池耗尽
**症状**：数据库连接等待时间增加，连接池使用率100%
**解决方案**：
1. 增加连接池大小
2. 优化SQL查询减少连接持有时间
3. 实现连接复用

#### 模式2：外部API延迟
**症状**：外部依赖响应时间波动大，超时增加
**解决方案**：
1. 增加超时时间和重试机制
2. 实现熔断和降级
3. 添加本地缓存减少外部调用

#### 模式3：服务间同步调用链过长
**症状**：调用链路深度增加，总延迟累积
**解决方案**：
1. 异步化非关键路径
2. 并行化独立操作
3. 减少不必要的服务调用

## 总结

本示例展示了如何使用trace-analyzer技能识别和分析支付系统中的性能瓶颈。通过系统的瓶颈分析，我们能够：

1. **准确识别瓶颈**：定位到payment-service和bank-gateway-service为主要瓶颈
2. **深入分析特征**：理解瓶颈的时间、业务和系统特征
3. **定位根本原因**：识别数据库竞争和外部依赖问题
4. **提供具体建议**：给出立即、短期和长期的优化方案
5. **建立验证机制**：确保优化效果可测量、可验证

通过定期执行瓶颈分析，可以：
- 预防性能问题发生
- 快速响应性能下降
- 持续优化系统性能
- 保障业务关键指标

trace-analyzer技能为分布式系统的性能管理和优化提供了强大的分析能力，是确保系统稳定高效运行的重要工具。