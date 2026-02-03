# 系统日志收集示例

## 场景描述

本示例演示如何使用data-collector技能从欧拉OS系统中收集多种类型的系统日志，包括系统消息日志、安全日志、应用日志等。场景基于一个需要故障诊断的生产服务器，需要收集最近24小时的日志数据进行分析。

## 前置条件

### 系统要求
- 欧拉OS 2.0或更高版本
- 对日志文件的读取权限
- 足够的磁盘空间存储收集的数据

### 配置要求
- witty-diagnosis-agent已安装并配置
- 系统日志位于标准位置（/var/log/）

## 执行步骤

### 步骤1：准备收集任务

定义要收集的日志源和参数：

```bash
claude witty-diagnosis:data-collector \
  --task-id log-collection-001 \
  --data-type logs \
  --log-sources /var/log/messages /var/log/secure /var/log/audit/audit.log \
  --time-range last_24_hours \
  --filter-level INFO WARN ERROR CRIT \
  --output-format json \
  --compress true \
  --max-size 100MB
```

### 步骤2：执行日志收集

使用以下命令执行收集：

```bash
claude witty-diagnosis:data-collector \
  --session-id syslog-collect-001 \
  --data-sources logs \
  --log-paths /var/log/messages:/var/log/secure:/var/log/audit/audit.log \
  --time-window "24h" \
  --severity-levels INFO WARN ERROR CRIT \
  --include-metadata true \
  --output-file /tmp/collected-logs-$(date +%Y%m%d-%H%M%S).json \
  --compression gzip
```

### 步骤3：验证收集结果

检查收集的数据：

```bash
# 查看收集的文件信息
ls -lh /tmp/collected-logs-*.json.gz

# 验证数据完整性
claude witty-diagnosis:data-collector --verify /tmp/collected-logs-*.json.gz

# 查看数据摘要
claude witty-diagnosis:data-collector --summary /tmp/collected-logs-*.json.gz
```

## 输入参数说明

### 必需参数
- `--data-sources`: 数据源类型（logs表示日志）
- `--log-paths`: 日志文件路径列表，用冒号分隔

### 可选参数
- `--time-window`: 时间窗口（如"24h"、"7d"、"1h"）
- `--severity-levels`: 日志级别过滤
- `--output-file`: 输出文件路径
- `--compression`: 压缩算法（gzip、none）
- `--include-metadata`: 是否包含元数据
- `--max-file-size`: 最大文件大小限制

## 预期输出

### 成功输出示例
```json
{
  "status": "success",
  "task_id": "log-collection-001",
  "execution_time": 45.2,
  "collected_data": {
    "type": "logs",
    "source_count": 3,
    "total_entries": 12560,
    "size_bytes": 1542890,
    "compressed_size": 452890,
    "time_range": {
      "start": "2026-02-02T10:30:00Z",
      "end": "2026-02-03T10:30:00Z"
    },
    "files": [
      {
        "path": "/tmp/collected-logs-20260203-103000.json.gz",
        "size": 452890,
        "entries": 12560,
        "sources": ["/var/log/messages", "/var/log/secure", "/var/log/audit/audit.log"]
      }
    ]
  },
  "metadata": {
    "skill": "data-collector",
    "version": "1.0.0",
    "timestamp": "2026-02-03T10:30:45Z"
  }
}
```

### 错误输出示例
```json
{
  "status": "error",
  "task_id": "log-collection-001",
  "error_code": "PERMISSION_DENIED",
  "error_message": "没有权限读取文件：/var/log/audit/audit.log",
  "partial_results": {
    "collected_sources": ["/var/log/messages", "/var/log/secure"],
    "failed_sources": ["/var/log/audit/audit.log"]
  }
}
```

## 故障排除

### 常见问题

#### 权限不足
**症状**: 返回PERMISSION_DENIED错误
**解决**: 使用sudo运行或调整文件权限

#### 日志文件不存在
**症状**: 返回FILE_NOT_FOUND错误
**解决**: 检查日志文件路径是否正确

#### 输出文件过大
**症状**: 超过max-file-size限制
**解决**: 调整时间范围或使用过滤条件

#### 时间格式错误
**症状**: 无法解析时间窗口参数
**解决**: 使用标准格式如"24h"、"7d"、"1h"

## 最佳实践

1. **定期收集**: 建立定期日志收集计划
2. **增量收集**: 使用时间戳进行增量收集，避免重复
3. **数据验证**: 收集后验证数据完整性和一致性
4. **存储管理**: 定期清理旧的收集数据
5. **错误处理**: 实现错误重试和部分成功处理

---

*示例版本：1.0.0*
*最后更新：2026-02-03*