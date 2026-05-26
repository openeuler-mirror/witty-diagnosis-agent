---
name: service-status-check
version: 1.0.0
description: 检查系统关键服务的运行状态，快速识别异常服务
metadata:
  keywords: ["服务状态", "systemctl", "服务检查", "系统服务", "服务监控"]
---

# 系统服务状态检查技能

> 快速检查系统关键服务的运行状态

## 概述 (Overview)

本技能用于检查系统关键服务的运行状态，包括网络、SSH、数据库等常用服务，快速识别异常服务，为系统故障排查提供基础信息。

## 何时使用此技能 (When to Use)

- **场景 1**：系统启动后检查服务状态
- **场景 2**：服务故障排查
- **场景 3**：系统维护前状态确认
- **场景 4**：远程协助时提供服务状态

## 使用方法 (Usage)

```bash
# 检查所有关键服务
./scripts/check_services.sh

# 检查指定服务
./scripts/check_services.sh sshd network

# 查看帮助
./scripts/check_services.sh --help
```

## 脚本说明

### 脚本位置

- `scripts/check_services.sh`

### 检查的服务列表

- sshd (SSH服务)
- network (网络服务)
- docker (容器服务)
- nginx (Web服务)
- mysql (数据库服务)
- postgresql (数据库服务)

## 注意事项

1. 需要root权限查看所有服务状态
2. 未安装的服务会显示为"未安装"
3. 支持自定义服务名称作为参数
