# 错误日志分析示例

## 场景描述

本示例演示如何使用log-analyzer技能分析生产系统中的错误日志，识别频繁出现的错误模式、异常趋势和潜在问题。场景基于一个运行欧拉OS的生产Web服务器，该系统最近出现了性能下降和间歇性错误。

## 前置条件

### 系统要求
- 欧拉OS 2.0或更高版本
- Python 3.8+环境
- 至少2GB可用内存
- 对日志文件的读取权限

### 配置要求
- witty-diagnosis-agent已安装并配置
- data-collector技能可用
- 系统日志位于标准位置（/var/log/）

### 数据准备
1. 确保系统日志文件存在且可读：
   - `/var/log/messages` - 系统消息日志
   - `/var/log/secure` - 安全认证日志
   - `/var/log/mysql/error.log` - MySQL错误日志（如果使用MySQL）
   - `/var/log/nginx/error.log` - Nginx错误日志（如果使用Nginx）

2. 收集要分析的日志数据（使用data-collector技能）：
   ```bash
   claude witty-diagnosis:data-collector --target system --data-sources logs --log-sources /var/log/messages /var/log/secure --output-format json
   ```

## 执行步骤

### 步骤1：准备分析输入

基于收集的日志数据，准备log-analyzer的输入。假设我们已经从data-collector获得了以下格式的日志数据：

```json
{
  "session_id": "error-analysis-prep-001",
  "log_data": {
    "source": "production-web-server",
    "format": "syslog",
    "entries": [
      {
        "timestamp": "2026-02-03T08:15:30Z",
        "hostname": "web-server-01",
        "facility": "kern",
        "severity": "ERROR",
        "message": "Disk I/O error on /dev/sda2: retrying operation",
        "source_file": "/var/log/messages",
        "line_number": 1234
      },
      {
        "timestamp": "2026-02-03T08:16:45Z",
        "hostname": "web-server-01",
        "facility": "daemon",
        "severity": "ERROR",
        "message": "MySQL server has gone away",
        "source_file": "/var/log/mysql/error.log",
        "line_number": 567
      },
      {
        "timestamp": "2026-02-03T08:17:20Z",
        "hostname": "web-server-01",
        "facility": "local7",
        "severity": "ERROR",
        "message": "nginx: [error] 10240#10240: *12345 connect() failed (111: Connection refused) while connecting to upstream",
        "source_file": "/var/log/nginx/error.log",
        "line_number": 890
      },
      {
        "timestamp": "2026-02-03T08:18:05Z",
        "hostname": "web-server-01",
        "facility": "auth",
        "severity": "WARN",
        "message": "Failed password for user deploy from 192.168.1.150",
        "source_file": "/var/log/secure",
        "line_number": 2345
      },
      {
        "timestamp": "2026-02-03T08:19:30Z",
        "hostname": "web-server-01",
        "facility": "kern",
        "severity": "ERROR",
        "message": "Disk I/O error on /dev/sda2: operation failed after 3 retries",
        "source_file": "/var/log/messages",
        "line_number": 1235
      },
      {
        "timestamp": "2026-02-03T08:20:15Z",
        "hostname": "web-server-01",
        "facility": "daemon",
        "severity": "WARN",
        "message": "MySQL connection pool exhausted, consider increasing max_connections",
        "source_file": "/var/log/mysql/error.log",
        "line_number": 568
      },
      {
        "timestamp": "2026-02-03T08:21:40Z",
        "hostname": "web-server-01",
        "facility": "local7",
        "severity": "ERROR",
        "message": "nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)",
        "source_file": "/var/log/nginx/error.log",
        "line_number": 891
      },
      {
        "timestamp": "2026-02-03T08:22:25Z",
        "hostname": "web-server-01",
        "facility": "auth",
        "severity": "WARN",
        "message": "Failed password for user root from 192.168.1.150",
        "source_file": "/var/log/secure",
        "line_number": 2346
      },
      {
        "timestamp": "2026-02-03T08:23:10Z",
        "hostname": "web-server-01",
        "facility": "kern",
        "severity": "CRIT",
        "message": "EXT4-fs error (device sda2): ext4_find_entry: reading directory #12345678 offset 0",
        "source_file": "/var/log/messages",
        "line_number": 1236
      },
      {
        "timestamp": "2026-02-03T08:24:55Z",
        "hostname": "web-server-01",
        "facility": "daemon",
        "severity": "ERROR",
        "message": "InnoDB: Operating system error number 28 in a file operation.",
        "source_file": "/var/log/mysql/error.log",
        "line_number": 569
      }
    ],
    "metadata": {
      "total_entries": 156,
      "time_range": {
        "start": "2026-02-03T08:00:00Z",
        "end": "2026-02-03T09:00:00Z"
      },
      "sources": [
        "/var/log/messages",
        "/var/log/secure",
        "/var/log/mysql/error.log",
        "/var/log/nginx/error.log"
      ]
    }
  }
}
```

### 步骤2：执行错误日志分析

使用log-analyzer技能分析错误日志：

```bash
claude witty-diagnosis:log-analyzer \
  --session-id error-analysis-001 \
  --analysis-types anomaly pattern correlation \
  --severity-levels ERROR CRIT WARN \
  --keyword-filters error fail timeout refused exhausted \
  --pattern-threshold 0.7 \
  --correlation-window 300 \
  --detailed-analysis true \
  --output-format json
```

### 步骤3：提供分析输入

将准备好的日志数据作为输入提供给log-analyzer技能：

```json
{
  "session_id": "error-analysis-001",
  "log_data": {
    "source": "production-web-server",
    "format": "syslog",
    "entries": [
      // ... 实际的156条日志条目
    ],
    "metadata": {
      "total_entries": 156,
      "time_range": {
        "start": "2026-02-03T08:00:00Z",
        "end": "2026-02-03T09:00:00Z"
      },
      "sources": [
        "/var/log/messages",
        "/var/log/secure",
        "/var/log/mysql/error.log",
        "/var/log/nginx/error.log"
      ]
    }
  },
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    "analysis_types": ["anomaly", "pattern", "correlation"],
    "log_format": "syslog",
    "severity_levels": ["ERROR", "CRIT", "WARN"],
    "keyword_filters": ["error", "fail", "timeout", "refused", "exhausted"],
    "pattern_threshold": 0.7,
    "correlation_window": 300,
    "detailed_analysis": true,
    "output_format": "json"
  },
  "metadata": {
    "request_id": "req-error-analysis-001",
    "timestamp": "2026-02-03T09:05:00Z",
    "environment": "production",
    "issue_description": "Web服务器出现间歇性错误和性能下降",
    "priority": "high"
  }
}
```

## 预期结果

### 分析结果摘要

log-analyzer技能应该返回以下类型的分析结果：

```json
{
  "status": "success",
  "session_id": "error-analysis-001",
  "execution_time": 12.5,
  "results": {
    "summary": {
      "total_logs_analyzed": 156,
      "analysis_types_performed": ["anomaly", "pattern", "correlation"],
      "anomalies_detected": 7,
      "patterns_identified": 4,
      "correlations_found": 3,
      "critical_issues": 2,
      "analysis_start_time": "2026-02-03T09:05:00Z",
      "analysis_end_time": "2026-02-03T09:05:12Z"
    },
    "parsing_results": {
      "format_detected": "syslog",
      "parsing_success_rate": 100.0,
      "fields_extracted": ["timestamp", "hostname", "facility", "severity", "message", "source_file"],
      "parsing_errors": 0
    },
    "anomaly_detection": {
      "total_anomalies": 7,
      "by_severity": {
        "critical": 2,
        "high": 3,
        "medium": 2,
        "low": 0
      },
      "anomalies": [
        {
          "id": "anomaly-disk-001",
          "type": "disk_filesystem_error",
          "severity": "critical",
          "description": "检测到严重的磁盘文件系统错误（EXT4-fs error）",
          "confidence": 0.96,
          "time_range": {
            "start": "2026-02-03T08:23:10Z",
            "end": "2026-02-03T08:23:10Z"
          },
          "evidence": [
            {
              "timestamp": "2026-02-03T08:23:10Z",
              "message": "EXT4-fs error (device sda2): ext4_find_entry: reading directory #12345678 offset 0",
              "source": "/var/log/messages",
              "severity": "CRIT"
            }
          ],
          "suggestions": [
            "立即检查磁盘/dev/sda2的文件系统完整性",
            "运行fsck检查并修复文件系统",
            "备份关键数据以防数据丢失",
            "考虑更换可能有问题的磁盘"
          ]
        },
        {
          "id": "anomaly-disk-io-001",
          "type": "disk_io_error_frequency",
          "severity": "high",
          "description": "磁盘I/O错误频率异常增高（3次/小时，基线<0.1次/小时）",
          "confidence": 0.88,
          "time_range": {
            "start": "2026-02-03T08:15:30Z",
            "end": "2026-02-03T08:19:30Z"
          },
          "frequency": {
            "expected": 0.1,
            "actual": 3.0,
            "deviation": 2900
          },
          "evidence": [
            {
              "timestamp": "2026-02-03T08:15:30Z",
              "message": "Disk I/O error on /dev/sda2: retrying operation",
              "source": "/var/log/messages",
              "severity": "ERROR"
            },
            {
              "timestamp": "2026-02-03T08:19:30Z",
              "message": "Disk I/O error on /dev/sda2: operation failed after 3 retries",
              "source": "/var/log/messages",
              "severity": "ERROR"
            }
          ],
          "suggestions": [
            "监控磁盘/dev/sda2的SMART状态",
            "检查磁盘IO性能指标",
            "考虑迁移数据到健康磁盘"
          ]
        },
        {
          "id": "anomaly-mysql-001",
          "type": "database_connection_issues",
          "severity": "high",
          "description": "检测到MySQL数据库连接问题集群",
          "confidence": 0.82,
          "time_range": {
            "start": "2026-02-03T08:16:45Z",
            "end": "2026-02-03T08:24:55Z"
          },
          "evidence": [
            {
              "timestamp": "2026-02-03T08:16:45Z",
              "message": "MySQL server has gone away",
              "source": "/var/log/mysql/error.log",
              "severity": "ERROR"
            },
            {
              "timestamp": "2026-02-03T08:20:15Z",
              "message": "MySQL connection pool exhausted, consider increasing max_connections",
              "source": "/var/log/mysql/error.log",
              "severity": "WARN"
            },
            {
              "timestamp": "2026-02-03T08:24:55Z",
              "message": "InnoDB: Operating system error number 28 in a file operation.",
              "source": "/var/log/mysql/error.log",
              "severity": "ERROR"
            }
          ],
          "suggestions": [
            "检查MySQL服务器状态和资源使用",
            "调整max_connections参数",
            "检查磁盘空间是否充足（错误28表示磁盘空间不足）"
          ]
        }
      ]
    },
    "pattern_recognition": {
      "total_patterns": 4,
      "patterns": [
        {
          "id": "pattern-disk-mysql-001",
          "type": "causal_sequence",
          "description": "磁盘错误后出现数据库问题的序列模式",
          "confidence": 0.75,
          "support": 0.67,
          "sequence": [
            "磁盘I/O错误",
            "MySQL连接问题",
            "InnoDB文件操作错误"
          ],
          "occurrences": 2,
          "time_distribution": {
            "mean_interval_seconds": 315,
            "std_dev_seconds": 45
          },
          "implication": "磁盘问题可能导致数据库操作失败"
        },
        {
          "id": "pattern-auth-001",
          "type": "brute_force_pattern",
          "description": "来自同一IP的认证失败模式",
          "confidence": 0.80,
          "support": 1.0,
          "sequence": [
            "Failed password for user deploy",
            "Failed password for user root"
          ],
          "occurrences": 1,
          "source_ip": "192.168.1.150",
          "time_window_seconds": 250,
          "implication": "可能的暴力破解尝试"
        }
      ]
    },
    "correlation_analysis": {
      "total_correlations": 3,
      "correlations": [
        {
          "id": "correlation-disk-nginx-001",
          "type": "temporal_correlation",
          "description": "磁盘错误与Nginx绑定失败的时间关联",
          "confidence": 0.78,
          "events": [
            {
              "type": "disk_error",
              "timestamp": "2026-02-03T08:19:30Z",
              "description": "磁盘I/O操作失败"
            },
            {
              "type": "nginx_bind_failure",
              "timestamp": "2026-02-03T08:21:40Z",
              "description": "Nginx绑定端口失败"
            }
          ],
          "time_lag_seconds": 130,
          "correlation_strength": 0.72,
          "possible_relationship": "磁盘问题可能导致进程异常终止和端口未释放"
        }
      ]
    },
    "time_series_analysis": {
      "trends": [
        {
          "metric": "error_logs_per_15min",
          "trend": "increasing",
          "slope": 2.8,
          "r_squared": 0.89,
          "description": "错误日志频率在分析时段内持续增加"
        }
      ],
      "periodic_patterns": [],
      "anomaly_points": 5
    },
    "recommendations": {
      "immediate_actions": [
        {
          "priority": "critical",
          "action": "立即检查并修复磁盘/dev/sda2的文件系统",
          "reason": "检测到严重的EXT4文件系统错误",
          "estimated_impact": "防止数据损坏和系统崩溃",
          "estimated_time": "30-60分钟",
          "risk_level": "high"
        },
        {
          "priority": "high",
          "action": "检查磁盘空间使用情况",
          "reason": "InnoDB报告磁盘空间不足错误（错误28）",
          "estimated_impact": "防止数据库操作失败",
          "estimated_time": "5-10分钟",
          "risk_level": "medium"
        }
      ],
      "investigation_areas": [
        {
          "area": "认证安全",
          "reason": "检测到来自192.168.1.150的疑似暴力破解尝试",
          "suggested_analysis": ["security-analyzer"],
          "priority": "medium"
        },
        {
          "area": "数据库连接管理",
          "reason": "MySQL连接池耗尽和连接问题",
          "suggested_analysis": ["metric-analyzer", "database-analyzer"],
          "priority": "high"
        }
      ],
      "monitoring_suggestions": [
        {
          "metric": "磁盘I/O错误率",
          "threshold": "> 0.5 errors/hour",
          "alert_level": "warning",
          "suggested_action": "自动通知运维团队"
        },
        {
          "metric": "文件系统错误",
          "threshold": "> 0 errors",
          "alert_level": "critical",
          "suggested_action": "立即介入检查"
        }
      ]
    }
  },
  "metadata": {
    "skill_name": "log-analyzer",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T09:05:12Z",
    "execution_mode": "detailed",
    "analysis_config": {
      "pattern_threshold": 0.7,
      "correlation_window": 300
    }
  }
}
```

### 关键发现总结

基于分析结果，可以总结以下关键发现：

1. **严重磁盘问题**：检测到EXT4文件系统错误，需要立即处理
2. **磁盘I/O异常**：I/O错误频率异常增高，可能预示硬件故障
3. **数据库连接问题**：MySQL出现多种连接和资源问题
4. **安全威胁**：检测到疑似暴力破解尝试
5. **关联模式**：磁盘问题与数据库、Web服务器问题存在时间关联

## 故障排除

### 常见问题

#### 问题1：日志格式无法识别
**症状**：log-analyzer返回`INVALID_LOG_FORMAT`错误
**解决方法**：
1. 明确指定`--log-format`参数
2. 检查日志数据是否包含必要的字段（如timestamp）
3. 使用`--log-format custom`并提供自定义解析规则

#### 问题2：分析时间过长
**症状**：分析过程超时或消耗过多时间
**解决方法**：
1. 减少分析的数据量（使用时间范围过滤）
2. 选择特定的分析类型而不是全部
3. 调整`--pattern-threshold`提高处理效率
4. 增加`--timeout`参数值

#### 问题3：分析结果不准确
**症状**：检测到的异常或模式不符合预期
**解决方法**：
1. 调整`--pattern-threshold`参数（降低值提高灵敏度）
2. 优化`--keyword-filters`包含更多相关关键词
3. 确保日志数据质量（时间戳准确、格式一致）
4. 使用`--detailed-analysis true`获取更多上下文信息

#### 问题4：内存使用过高
**症状**：分析过程中内存使用异常增高
**解决方法**：
1. 分块处理大规模日志数据
2. 使用流式处理模式（如果支持）
3. 增加系统可用内存
4. 优化分析参数减少中间数据

### 调试技巧

1. **启用详细日志**：使用`--verbosity debug`获取详细执行日志
2. **分步分析**：先执行单一分析类型（如`--analysis-types anomaly`），验证后再添加其他类型
3. **样本测试**：使用少量样本数据测试分析配置
4. **结果验证**：手动验证关键发现，调整参数提高准确性
5. **性能监控**：监控分析过程中的资源使用情况

### 最佳实践

1. **定期分析**：建立定期日志分析机制，及时发现潜在问题
2. **基线建立**：分析正常时期的日志建立基线，便于异常检测
3. **结果集成**：将分析结果集成到监控和告警系统
4. **持续优化**：根据实际效果持续优化分析参数和规则
5. **知识积累**：将验证有效的分析模式添加到知识库

## 后续步骤

基于分析结果，建议执行以下后续步骤：

1. **立即行动**：
   - 执行磁盘文件系统检查和修复
   - 清理磁盘空间
   - 封锁可疑IP地址

2. **深入调查**：
   - 使用metric-analyzer分析系统性能指标
   - 使用trace-analyzer分析应用调用链
   - 进行安全审计和漏洞扫描

3. **预防措施**：
   - 建立磁盘健康监控
   - 优化数据库连接配置
   - 加强系统安全配置

4. **持续改进**：
   - 建立自动化日志分析流程
   - 完善监控和告警机制
   - 定期进行系统健康检查

---

*示例版本：1.0.0*
*最后更新：2026-02-03*