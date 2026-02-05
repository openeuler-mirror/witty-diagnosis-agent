---
name: data-collector
description: 多源系统数据采集技能，负责从欧拉OS系统收集日志、指标、进程、网络和配置信息
version: 1.0.0
category: core
author: witty-diagnosis-team
created: 2026-02-03
updated: 2026-02-03
tags:
  - data-collection
  - system-monitoring
  - metrics
  - logs
  - euler-os
  - diagnostics
---

# 数据采集器 - 多源系统数据采集技能

## 概述

数据采集器技能是witty-diagnosis-agent项目的核心数据收集组件，专门设计用于从欧拉OS系统多源收集全面的运行数据。本技能支持模块化数据采集，可根据需求选择性地收集不同类型的数据，为后续的诊断分析提供丰富、准确的数据基础。

主要功能包括：
1. **系统日志收集**：从/var/log等标准位置收集系统、应用和安全日志
2. **性能指标采集**：实时收集CPU、内存、磁盘、网络等性能指标
3. **进程信息收集**：获取运行中进程的详细信息，包括资源使用情况
4. **网络状态检查**：收集网络连接、端口监听、路由表等信息
5. **配置信息收集**：收集系统配置、服务状态、软件包信息等

本技能是诊断流程的基础环节，为log-analyzer、metric-analyzer、fault-localization等后续分析技能提供数据输入。

## 使用时机

### 应该使用此技能的情况：
- 需要为系统诊断收集基础数据时
- 作为定期巡检的数据收集阶段
- 在性能问题分析前收集系统状态快照
- 故障排查时收集相关系统信息
- 与其他诊断技能配合使用，提供数据源
- 建立系统性能基线需要历史数据时

### 不应该使用此技能的情况：
- 只需要单一类型数据时（使用专门的收集工具）
- 实时监控场景（使用专门的监控系统）
- 需要深度日志分析时（使用log-analyzer技能）
- 需要性能趋势分析时（使用metric-analyzer技能）

## 输入要求

### 必需输入

| 参数名 | 类型 | 描述 | 示例值 |
|--------|------|------|--------|
| `session_id` | string | 诊断会话ID | `"data-collection-001"` |
| `target` | string | 数据收集目标类型 | `"system"`, `"network"`, `"storage"`, `"security"`, `"all"` |

### 可选输入

| 参数名 | 类型 | 默认值 | 描述 |
|--------|------|--------|------|
| `timeout` | number | `300` | 执行超时时间（秒） |
| `verbosity` | string | `"info"` | 日志详细程度：`"debug"`, `"info"`, `"warn"`, `"error"` |
| `data_sources` | array | `["logs", "metrics", "processes", "network", "config"]` | 要收集的数据源列表 |
| `log_sources` | array | `["/var/log/messages", "/var/log/syslog"]` | 要收集的日志文件路径 |
| `metric_interval` | number | `5` | 指标收集间隔（秒） |
| `metric_samples` | number | `3` | 指标采样次数 |
| `output_format` | string | `"json"` | 输出格式：`"json"`, `"yaml"`, `"text"` |
| `compress_output` | boolean | `false` | 是否压缩输出数据 |
| `max_data_size_mb` | number | `10` | 最大数据大小限制（MB） |

### 输入格式示例

```json
{
  "session_id": "data-collection-session-001",
  "target": "system",
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    "data_sources": ["logs", "metrics", "processes"],
    "log_sources": [
      "/var/log/messages",
      "/var/log/syslog",
      "/var/log/secure"
    ],
    "metric_interval": 5,
    "metric_samples": 3,
    "output_format": "json",
    "max_data_size_mb": 10
  },
  "metadata": {
    "request_id": "req-data-001",
    "timestamp": "2026-02-03T17:30:00Z",
    "environment": "production",
    "user": {
      "id": "admin",
      "role": "system-admin"
    }
  }
}
```

## 执行步骤

### 1. 初始化阶段
- **参数验证**：验证输入参数的有效性和完整性
- **权限检查**：检查执行用户对目标数据源的访问权限
- **环境准备**：创建临时工作目录，初始化日志记录器
- **依赖检查**：验证所需系统命令的可用性（top, ps, netstat, df等）
- **资源评估**：评估系统资源状态，确保收集过程不会影响系统性能

### 2. 数据收集阶段（模块化执行）
根据`data_sources`参数选择性地执行以下收集模块：

#### 日志收集模块（logs）
- **系统日志**：收集/var/log/messages, /var/log/syslog等
- **安全日志**：收集/var/log/secure, /var/log/auth.log等
- **应用日志**：根据配置收集特定应用日志
- **日志过滤**：支持时间范围、日志级别、关键字过滤
- **日志解析**：解析日志格式，提取结构化信息

#### 指标收集模块（metrics）
- **CPU指标**：使用`top`或`/proc/stat`收集CPU使用率、负载
- **内存指标**：使用`free`或`/proc/meminfo`收集内存使用情况
- **磁盘指标**：使用`df`, `iostat`收集磁盘空间和IO性能
- **网络指标**：使用`sar`, `netstat`收集网络流量和连接数
- **采样机制**：按指定间隔进行多次采样，计算平均值

#### 进程收集模块（processes）
- **进程列表**：使用`ps aux`收集所有运行进程
- **资源使用**：收集每个进程的CPU、内存使用情况
- **进程关系**：分析进程父子关系和进程树
- **服务进程**：识别系统服务进程和关键应用进程

#### 网络收集模块（network）
- **连接状态**：使用`netstat`或`ss`收集网络连接信息
- **端口监听**：收集所有监听端口和服务信息
- **路由信息**：收集路由表和网络接口配置
- **DNS配置**：收集DNS服务器和解析配置

#### 配置收集模块（config）
- **系统配置**：收集/etc目录下的关键配置文件
- **服务状态**：使用`systemctl`收集服务运行状态
- **软件包信息**：收集已安装软件包和版本信息
- **内核参数**：收集sysctl配置和内核模块信息

### 3. 数据处理阶段
- **数据清洗**：去除重复、无效或敏感数据
- **格式标准化**：将不同来源的数据转换为统一格式
- **数据关联**：建立不同数据源之间的关联关系
- **大小控制**：检查数据大小，必要时进行压缩或截断
- **完整性验证**：验证收集数据的完整性和一致性

### 4. 结果生成阶段
- **结果组装**：将各模块数据组装为统一结构
- **元数据添加**：添加收集时间、数据源、版本等元数据
- **性能统计**：记录收集过程的性能指标
- **资源清理**：清理临时文件和中间数据
- **输出生成**：按指定格式生成最终输出

## 输出格式

### 成功输出格式

```json
{
  "status": "success",
  "session_id": "data-collection-session-001",
  "execution_time": 45.2,
  "results": {
    "summary": {
      "total_data_sources": 5,
      "successful_sources": 5,
      "failed_sources": 0,
      "total_data_size_mb": 8.5,
      "collection_start_time": "2026-02-03T17:30:00Z",
      "collection_end_time": "2026-02-03T17:30:45Z"
    },
    "data": {
      "logs": {
        "total_entries": 1250,
        "sources": [
          {
            "path": "/var/log/messages",
            "entries": 850,
            "size_kb": 420,
            "time_range": {
              "start": "2026-02-03T16:30:00Z",
              "end": "2026-02-03T17:30:00Z"
            }
          },
          {
            "path": "/var/log/secure",
            "entries": 400,
            "size_kb": 180,
            "time_range": {
              "start": "2026-02-03T16:45:00Z",
              "end": "2026-02-03T17:30:00Z"
            }
          }
        ],
        "sample_entries": [
          {
            "timestamp": "2026-02-03T17:25:30Z",
            "level": "ERROR",
            "message": "Disk write error on /dev/sda1",
            "source": "/var/log/messages"
          }
        ]
      },
      "metrics": {
        "cpu": {
          "usage_percent": 45.2,
          "load_1min": 1.2,
          "load_5min": 1.5,
          "load_15min": 1.3,
          "cores": 8,
          "frequency_mhz": 2400
        },
        "memory": {
          "total_bytes": 17179869184,
          "used_bytes": 11596411699,
          "free_bytes": 5583457485,
          "available_bytes": 6442450944,
          "usage_percent": 67.5
        },
        "disk": [
          {
            "device": "/dev/sda1",
            "mount_point": "/",
            "total_bytes": 53687091200,
            "used_bytes": 26843545600,
            "free_bytes": 26843545600,
            "usage_percent": 50.0
          }
        ],
        "network": {
          "interfaces": [
            {
              "name": "eth0",
              "ip_address": "192.168.1.100",
              "rx_bytes": 1024000,
              "tx_bytes": 512000
            }
          ]
        }
      },
      "processes": {
        "total_count": 156,
        "user_processes": 45,
        "system_processes": 111,
        "top_processes": [
          {
            "pid": 1234,
            "name": "java",
            "user": "appuser",
            "cpu_percent": 25.5,
            "memory_percent": 15.2,
            "command": "/usr/bin/java -Xmx2g -jar app.jar"
          }
        ]
      },
      "network_info": {
        "connections": {
          "total": 85,
          "established": 42,
          "listening": 15
        },
        "listening_ports": [
          {
            "port": 22,
            "protocol": "tcp",
            "service": "ssh",
            "process": "sshd"
          }
        ]
      },
      "config": {
        "system_info": {
          "os_name": "EulerOS",
          "os_version": "2.0",
          "kernel_version": "4.19.90",
          "hostname": "server-01"
        },
        "services": {
          "running": 45,
          "failed": 2
        }
      }
    },
    "performance": {
      "collection_times": {
        "logs": 5.2,
        "metrics": 15.8,
        "processes": 2.1,
        "network": 3.5,
        "config": 4.8
      },
      "resource_usage": {
        "cpu_percent": 12.5,
        "memory_mb": 256
      }
    }
  },
  "metadata": {
    "skill_name": "data-collector",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:45Z",
    "execution_mode": "standard",
    "data_format_version": "1.0.0"
  }
}
```

### 部分成功输出格式

```json
{
  "status": "partial",
  "session_id": "data-collection-session-001",
  "execution_time": 35.1,
  "results": {
    "summary": {
      "total_data_sources": 5,
      "successful_sources": 4,
      "failed_sources": 1,
      "total_data_size_mb": 6.8
    },
    "data": {
      // 成功收集的数据
    },
    "partial_results": {
      "successful_sources": ["logs", "metrics", "processes", "network"],
      "failed_sources": ["config"],
      "failure_reasons": {
        "config": "权限不足，无法读取/etc目录"
      }
    }
  },
  "metadata": {
    "skill_name": "data-collector",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:35Z"
  }
}
```

### 错误输出格式

```json
{
  "status": "error",
  "session_id": "data-collection-session-001",
  "execution_time": 5.1,
  "error_code": "PERMISSION_DENIED",
  "error_message": "执行用户权限不足，无法收集系统日志",
  "details": {
    "failed_step": "数据收集阶段",
    "failed_module": "logs",
    "error_context": {
      "target_file": "/var/log/messages",
      "required_permission": "root",
      "current_user": "appuser"
    }
  },
  "suggestions": [
    "使用具有适当权限的用户执行",
    "配置sudo权限允许读取日志文件",
    "调整log_sources参数排除需要特权的文件"
  ],
  "metadata": {
    "skill_name": "data-collector",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:05Z"
  }
}
```

### 输出字段说明

| 字段名 | 类型 | 必需 | 描述 |
|--------|------|------|------|
| `status` | string | 是 | 执行状态：`"success"`, `"partial"`, `"error"` |
| `session_id` | string | 是 | 诊断会话ID |
| `execution_time` | number | 是 | 执行时间（秒） |
| `results.summary` | object | 是 | 收集结果摘要信息 |
| `results.data` | object | 是 | 收集的具体数据 |
| `results.performance` | object | 否 | 收集过程性能指标 |
| `results.partial_results` | object | 否 | 部分成功时的详细信息 |
| `metadata` | object | 是 | 元数据信息 |
| `error_code` | string | 否 | 错误代码（仅错误时） |
| `error_message` | string | 否 | 错误描述（仅错误时） |
| `details` | object | 否 | 详细错误信息（仅错误时） |
| `suggestions` | array | 否 | 修复建议（仅错误时） |

## 示例

### 示例1：基础数据收集

**场景描述**：
对生产服务器进行全面的系统数据收集，用于后续性能分析。

**命令调用**：
```bash
claude witty-diagnosis:data-collector --target system --data-sources logs metrics processes
```

**输入数据**：
```json
{
  "session_id": "prod-data-collection-001",
  "target": "system",
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    "data_sources": ["logs", "metrics", "processes"],
    "log_sources": [
      "/var/log/messages",
      "/var/log/syslog",
      "/var/log/secure"
    ],
    "metric_interval": 5,
    "metric_samples": 3,
    "max_data_size_mb": 10
  },
  "metadata": {
    "request_id": "req-prod-001",
    "environment": "production",
    "purpose": "performance_analysis"
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "prod-data-collection-001",
  "execution_time": 28.5,
  "results": {
    "summary": {
      "total_data_sources": 3,
      "successful_sources": 3,
      "failed_sources": 0,
      "total_data_size_mb": 7.2
    },
    "data": {
      "logs": {
        "total_entries": 980,
        "sources": [...]
      },
      "metrics": {
        "cpu": {"usage_percent": 38.5, ...},
        "memory": {"usage_percent": 62.3, ...},
        "disk": [...],
        "network": {...}
      },
      "processes": {
        "total_count": 142,
        "top_processes": [...]
      }
    }
  },
  "metadata": {
    "skill_name": "data-collector",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

### 示例2：针对性网络数据收集

**场景描述**：
针对网络问题进行诊断，专门收集网络相关数据。

**命令调用**：
```bash
claude witty-diagnosis:data-collector --target network --data-sources network metrics --metric-interval 2 --metric-samples 5
```

**输入数据**：
```json
{
  "session_id": "network-diagnosis-001",
  "target": "network",
  "parameters": {
    "timeout": 180,
    "data_sources": ["network", "metrics"],
    "metric_interval": 2,
    "metric_samples": 5,
    "output_format": "json"
  },
  "metadata": {
    "request_id": "req-network-001",
    "issue_description": "网络延迟异常增高",
    "priority": "high"
  }
}
```

**预期输出**：
```json
{
  "status": "success",
  "session_id": "network-diagnosis-001",
  "execution_time": 12.8,
  "results": {
    "summary": {
      "total_data_sources": 2,
      "successful_sources": 2,
      "failed_sources": 0,
      "total_data_size_mb": 3.5
    },
    "data": {
      "network_info": {
        "connections": {
          "total": 92,
          "established": 48,
          "listening": 18
        },
        "listening_ports": [...],
        "interface_stats": [...],
        "routing_table": [...]
      },
      "metrics": {
        "network": {
          "interfaces": [
            {
              "name": "eth0",
              "rx_bytes_per_sec": 1250000,
              "tx_bytes_per_sec": 850000,
              "rx_packets_per_sec": 1200,
              "tx_packets_per_sec": 800,
              "errors": 0,
              "dropped": 2
            }
          ]
        }
      }
    }
  },
  "metadata": {
    "skill_name": "data-collector",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}
```

## 注意事项

### 安全注意事项
- **权限管理**：需要适当的系统权限来访问日志文件、进程信息和系统配置
- **敏感数据**：自动过滤密码、密钥等敏感信息，支持自定义脱敏规则
- **数据存储**：临时数据在会话结束后自动清理，不持久化存储
- **访问控制**：支持配置白名单，限制可访问的数据源
- **审计日志**：记录所有数据收集操作，支持安全审计

### 性能注意事项
- **资源消耗**：数据收集过程会消耗CPU、内存和IO资源，建议在系统负载较低时执行
- **执行时间**：完整数据收集通常需要30-60秒，可通过调整参数控制
- **并发限制**：不建议同时执行多个数据收集任务，避免资源竞争
- **数据大小**：通过`max_data_size_mb`参数控制输出数据大小，避免内存溢出
- **采样频率**：指标收集间隔和采样次数影响数据精度和资源消耗

### 环境要求
- **操作系统**：欧拉OS 2.0或更高版本，兼容其他Linux发行版
- **系统命令**：需要top, ps, netstat/ss, df, free, iostat等命令
- **权限要求**：根据收集的数据类型需要相应的读取权限
- **存储空间**：需要临时存储空间，建议至少100MB可用空间
- **网络条件**：网络数据收集需要网络接口正常工作

### 限制和约束
- **数据范围**：只能收集本地系统数据，不支持远程收集
- **实时性**：非实时监控工具，适合快照式数据收集
- **日志轮转**：可能无法收集已被轮转或删除的旧日志
- **容器环境**：在容器内运行时只能收集容器内部数据
- **自定义日志**：需要明确配置才能收集非标准位置的日志文件

## 测试用例

### 测试1：完整数据收集测试
- **测试目的**：验证技能在正常系统上的完整数据收集能力
- **输入数据**：包含所有数据源的完整请求
- **预期输出**：成功状态，包含所有数据类型的完整结果
- **验证点**：
  - 所有配置的数据源都成功收集
  - 输出格式符合规范
  - 数据完整性检查通过
  - 执行时间在预期范围内（<60秒）

### 测试2：模块化收集测试
- **测试目的**：验证选择性数据收集功能
- **输入数据**：只请求日志和指标数据
- **预期输出**：成功状态，仅包含请求的数据类型
- **验证点**：
  - 正确识别并只收集请求的数据源
  - 未请求的数据源不包含在输出中
  - 资源消耗与收集范围匹配

### 测试3：权限不足测试
- **测试目的**：验证权限不足时的错误处理
- **输入数据**：使用非特权用户请求需要root权限的数据
- **预期输出**：部分成功或错误状态，清晰的权限错误信息
- **验证点**：
  - 优雅处理权限错误
  - 提供明确的错误信息和建议
  - 已收集的数据仍然可用（部分成功时）

### 测试4：性能边界测试
- **测试目的**：验证在大数据量下的性能表现
- **输入数据**：收集大量日志数据（>100MB）
- **预期输出**：成功状态，数据大小受控
- **验证点**：
  - 数据大小不超过配置限制
  - 内存使用在可控范围内
  - 执行时间可接受

### 测试5：超时处理测试
- **测试目的**：验证超时机制的有效性
- **输入数据**：设置很短的超时时间（5秒）
- **预期输出**：超时错误或部分结果
- **验证点**：
  - 在超时前优雅停止
  - 清理临时资源
  - 提供有意义的超时错误信息

## 相关技能

### 前置技能
- 无（此技能通常是数据收集流程的起点）

### 后置技能
- **log-analyzer**：对收集的日志数据进行深度分析
- **metric-analyzer**：对性能指标进行趋势分析和异常检测
- **fault-localization**：基于收集的数据进行故障定位
- **root-cause-analysis**：使用收集的数据进行根因分析
- **knowledge-base**：将收集的数据存储到知识库建立基线

### 替代技能
- 无直接替代技能，但可以与其他监控工具（如Prometheus、ELK）配合使用

### 补充技能
- **intelligent-inspection**：定期自动执行数据收集
- **config-manager**：管理数据收集的配置和策略
- **controlled-repair**：基于收集的数据执行修复操作

## 更新日志

### 版本 1.0.0 (2026-02-03)
- 初始版本发布
- 实现五大数据源收集：日志、指标、进程、网络、配置
- 支持模块化数据收集
- 完整的错误处理和权限管理
- 符合项目数据格式规范
- 包含全面的测试用例

### 版本 1.1.0 (计划中)
- 添加容器环境数据收集支持
- 支持远程数据收集（SSH）
- 添加数据压缩和加密选项
- 增强数据过滤和脱敏功能
- 添加数据质量评估指标

### 版本 1.2.0 (计划中)
- 支持流式数据收集
- 添加自定义数据收集插件
- 增强性能监控和调优
- 支持数据收集计划任务
- 添加数据版本管理和比对

---

*文档版本：1.0.0*
*最后更新：2026-02-03*