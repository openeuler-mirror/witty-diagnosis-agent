# 系统指标收集示例

## 场景描述

本示例演示如何使用data-collector技能从欧拉OS系统中收集性能指标数据，包括CPU使用率、内存使用、磁盘IO、网络流量等。场景基于一个需要性能分析和容量规划的生产服务器，需要收集最近1小时的详细指标数据。

## 前置条件

### 系统要求
- 欧拉OS 2.0或更高版本
- 系统监控工具已安装（如sysstat、prometheus-node-exporter等）
- 足够的系统资源执行数据收集

### 配置要求
- witty-diagnosis-agent已安装并配置
- 监控数据源可访问

## 执行步骤

### 步骤1：准备指标收集任务

定义要收集的指标类型和参数：

```bash
claude witty-diagnosis:data-collector \
  --task-id metrics-collection-001 \
  --data-type metrics \
  --metric-sources system process disk network \
  --collection-interval 10s \
  --duration 1h \
  --output-format json \
  --aggregation 1m \
  --include-histograms true
```

### 步骤2：执行指标收集

使用以下命令执行收集：

```bash
claude witty-diagnosis:data-collector \
  --session-id metrics-collect-001 \
  --data-sources metrics \
  --metric-types cpu memory disk_io network_io process_count \
  --collection-frequency 10 \
  --duration-minutes 60 \
  --sampling-rate 1 \
  --include-system-info true \
  --output-file /tmp/collected-metrics-$(date +%Y%m%d-%H%M%S).json \
  --format json-compact
```

### 步骤3：验证收集结果

检查收集的指标数据：

```bash
# 查看收集的文件信息
ls -lh /tmp/collected-metrics-*.json

# 验证数据完整性
claude witty-diagnosis:data-collector --verify-metrics /tmp/collected-metrics-*.json

# 查看数据摘要
claude witty-diagnosis:data-collector --metrics-summary /tmp/collected-metrics-*.json
```

## 输入参数说明

### 必需参数
- `--data-sources`: 数据源类型（metrics表示指标）
- `--metric-types`: 指标类型列表，用空格分隔

### 可选参数
- `--collection-frequency`: 收集频率（秒）
- `--duration-minutes`: 收集持续时间（分钟）
- `--sampling-rate`: 采样率（0-1之间）
- `--output-file`: 输出文件路径
- `--format`: 输出格式（json、json-compact、csv）
- `--include-system-info`: 是否包含系统信息
- `--process-filter`: 进程过滤条件

## 预期输出

### 成功输出示例
```json
{
  "status": "success",
  "task_id": "metrics-collection-001",
  "execution_time": 68.5,
  "collected_data": {
    "type": "metrics",
    "metric_count": 5,
    "total_samples": 21600,
    "size_bytes": 2890450,
    "time_range": {
      "start": "2026-02-03T09:30:00Z",
      "end": "2026-02-03T10:30:00Z"
    },
    "metrics_summary": {
      "cpu": {
        "samples": 360,
        "min": 12.5,
        "max": 98.3,
        "avg": 45.7,
        "unit": "percent"
      },
      "memory": {
        "samples": 360,
        "min": 2456,
        "max": 3120,
        "avg": 2789,
        "unit": "MB"
      },
      "disk_io": {
        "samples": 360,
        "read_min": 0,
        "read_max": 45200,
        "write_min": 0,
        "write_max": 28900,
        "unit": "KB/s"
      },
      "network_io": {
        "samples": 360,
        "rx_min": 120,
        "rx_max": 45200,
        "tx_min": 80,
        "tx_max": 28900,
        "unit": "KB/s"
      },
      "process_count": {
        "samples": 360,
        "min": 156,
        "max": 189,
        "avg": 172,
        "unit": "count"
      }
    },
    "files": [
      {
        "path": "/tmp/collected-metrics-20260203-103000.json",
        "size": 2890450,
        "samples": 21600,
        "metrics": ["cpu", "memory", "disk_io", "network_io", "process_count"]
      }
    ]
  },
  "metadata": {
    "skill": "data-collector",
    "version": "1.0.0",
    "timestamp": "2026-02-03T10:30:45Z",
    "system_info": {
      "hostname": "production-server-01",
      "os_version": "EulerOS 2.0",
      "cpu_cores": 8,
      "memory_total": "16GB",
      "disk_total": "500GB"
    }
  }
}
```

### 错误输出示例
```json
{
  "status": "error",
  "task_id": "metrics-collection-001",
  "error_code": "COLLECTION_FAILED",
  "error_message": "无法收集磁盘IO指标：设备/dev/sda不存在",
  "partial_results": {
    "collected_metrics": ["cpu", "memory", "network_io", "process_count"],
    "failed_metrics": ["disk_io"]
  }
}
```

## 支持的指标类型

### 系统级指标
- `cpu`: CPU使用率（用户、系统、空闲、等待）
- `memory`: 内存使用（总量、使用量、缓存、交换）
- `disk`: 磁盘使用（各分区使用率、inode使用）
- `disk_io`: 磁盘IO（读写速率、IOPS、延迟）
- `network_io`: 网络IO（接收/发送速率、包数、错误数）
- `load`: 系统负载（1分钟、5分钟、15分钟）

### 进程级指标
- `process_count`: 进程总数
- `process_cpu`: 各进程CPU使用
- `process_memory`: 各进程内存使用
- `process_io`: 各进程IO使用

### 应用级指标
- `service_status`: 服务状态
- `port_listening`: 端口监听状态
- `log_rotation`: 日志轮转状态

## 故障排除

### 常见问题

#### 指标收集失败
**症状**: 返回COLLECTION_FAILED错误
**解决**: 检查监控工具是否安装并运行

#### 采样率过高
**症状**: 系统负载过高或收集超时
**解决**: 降低收集频率或采样率

#### 数据不准确
**症状**: 指标值异常或不符合预期
**解决**: 验证监控工具配置和数据源

#### 输出文件过大
**症状**: 收集的数据量过大
**解决**: 减少指标类型、缩短持续时间或提高采样率

## 最佳实践

1. **合理采样**: 根据需求选择适当的收集频率
2. **数据过滤**: 只收集必要的指标类型
3. **存储优化**: 使用合适的输出格式和压缩
4. **监控收集过程**: 监控收集任务本身的资源使用
5. **数据质量**: 定期验证收集数据的准确性和完整性

## 进阶用法

### 实时指标流
```bash
# 实时流式收集指标
claude witty-diagnosis:data-collector \
  --data-sources metrics \
  --metric-types cpu memory \
  --streaming true \
  --stream-interval 5 \
  --duration 0 \
  --output-stream stdout
```

### 条件触发收集
```bash
# 当CPU使用率超过阈值时触发收集
claude witty-diagnosis:data-collector \
  --data-sources metrics \
  --trigger-condition "cpu.usage > 80" \
  --trigger-duration "5m" \
  --metric-types all \
  --collection-frequency 1
```

### 多主机收集
```bash
# 从多个主机收集指标
claude witty-diagnosis:data-collector \
  --data-sources metrics \
  --target-hosts server01:server02:server03 \
  --metric-types system \
  --parallel true \
  --output-dir /tmp/metrics-collection
```

---

*示例版本：1.0.0*
*最后更新：2026-02-03*