# 安全重启服务示例

## 场景描述

本示例演示如何使用controlled-repair技能安全地重启一个Web服务（以nginx为例）。在生产环境中，服务重启是一个常见但需要谨慎执行的操作，不当的重启可能导致服务中断时间过长或数据丢失。

**场景特点**：
- 生产环境nginx Web服务
- 服务出现内存泄漏问题
- 需要在业务低峰期执行
- 要求最小化服务中断时间
- 需要确保重启后服务正常运行

## 前置条件

### 系统要求
- 欧拉OS 2.0或更高版本
- nginx服务已安装并运行
- 系统具有足够的权限执行服务管理操作

### 配置要求
- witty-diagnosis-agent已正确安装和配置
- 用户具有执行服务重启的权限（root或sudo权限）
- 备份目录有足够的磁盘空间

### 数据准备
- 确认nginx服务当前运行状态
- 识别业务低峰期时间窗口
- 准备服务验证测试用例

## 执行步骤

### 1. 准备修复请求

创建修复请求JSON文件 `restart-nginx-request.json`：

```json
{
  "session_id": "nginx-restart-example-001",
  "target": "service",
  "repair_action": "restart",
  "repair_target": "nginx.service",
  "parameters": {
    "timeout": 180,
    "verbosity": "info",
    "require_approval": false,
    "auto_rollback": true,
    "rollback_timeout": 60,
    "verification_interval": 3,
    "verification_attempts": 5,
    "risk_threshold": "low",
    "dry_run": false,
    "backup_before_repair": true,
    "backup_location": "/var/backups/witty-diagnosis"
  },
  "metadata": {
    "request_id": "req-nginx-example-001",
    "environment": "production",
    "time_window": "maintenance",
    "user": {
      "id": "admin",
      "role": "system-admin"
    },
    "diagnosis_result": {
      "root_cause": "nginx worker进程内存泄漏",
      "confidence": 0.92,
      "recommended_action": "重启nginx服务释放内存"
    }
  }
}
```

### 2. 执行修复操作

使用Claude Code执行修复操作：

```bash
# 方式1：直接使用命令行参数
claude witty-diagnosis:controlled-repair \
  --target service \
  --repair-action restart \
  --repair-target nginx.service \
  --timeout 180 \
  --auto-rollback true \
  --verification-interval 3 \
  --verification-attempts 5 \
  --backup-before-repair true \
  --backup-location "/var/backups/witty-diagnosis"

# 方式2：使用JSON输入文件
claude witty-diagnosis:controlled-repair --input-file restart-nginx-request.json
```

### 3. 监控执行过程

修复操作执行过程中，可以监控以下关键指标：

1. **权限检查**：验证执行用户是否有重启nginx服务的权限
2. **风险评估**：评估重启操作的风险等级
3. **备份创建**：创建nginx配置和状态的备份
4. **服务停止**：优雅停止nginx服务
5. **服务启动**：启动nginx服务
6. **效果验证**：验证服务是否正常运行

### 4. 验证修复结果

修复完成后，检查以下验证点：

```bash
# 检查服务状态
systemctl status nginx.service

# 检查端口监听
netstat -tlnp | grep :80

# 测试HTTP响应
curl -I http://localhost

# 检查错误日志
tail -20 /var/log/nginx/error.log
```

## 预期结果

### 成功执行结果

修复操作成功执行后，应获得类似以下输出：

```json
{
  "status": "success",
  "session_id": "nginx-restart-example-001",
  "execution_time": 32.5,
  "results": {
    "summary": {
      "repair_action": "restart",
      "repair_target": "nginx.service",
      "repair_status": "completed",
      "risk_level": "low",
      "approval_required": false,
      "backup_created": true,
      "rollback_prepared": true,
      "verification_passed": true,
      "service_downtime_seconds": 8.7,
      "start_time": "2026-02-03T02:30:00Z",
      "end_time": "2026-02-03T02:30:32Z"
    },
    "execution_details": {
      "phases": {
        "initialization": {
          "status": "completed",
          "permission_check": "passed",
          "risk_assessment": {
            "level": "low",
            "factors": ["常规服务重启", "维护时段", "有完整备份"]
          }
        },
        "safety_control": {
          "status": "completed",
          "target_locked": true,
          "pre_checks_passed": true
        },
        "repair_execution": {
          "status": "completed",
          "steps": [
            {
              "name": "service_status_check",
              "status": "completed",
              "result": "service_running",
              "details": "nginx.service: active (running)"
            },
            {
              "name": "graceful_stop",
              "status": "completed",
              "result": "service_stopped",
              "duration_seconds": 5.2,
              "details": "nginx.service: inactive (dead)"
            },
            {
              "name": "service_start",
              "status": "completed",
              "result": "service_started",
              "duration_seconds": 3.5,
              "details": "nginx.service: active (running)"
            }
          ]
        },
        "verification": {
          "status": "completed",
          "checks": [
            {
              "name": "service_status",
              "status": "passed",
              "result": "active (running)",
              "details": "nginx.service: active (running) since Thu 2026-02-03 02:30:08 UTC"
            },
            {
              "name": "port_listening",
              "status": "passed",
              "result": "port_80_listening",
              "details": "tcp 0 0 0.0.0.0:80 0.0.0.0:* LISTEN"
            },
            {
              "name": "http_response",
              "status": "passed",
              "result": "http_200_ok",
              "response_time_ms": 45,
              "details": "HTTP/1.1 200 OK"
            }
          ]
        }
      },
      "backup_info": {
        "created": true,
        "location": "/var/backups/witty-diagnosis/nginx-20260203-023000.tar.gz",
        "size_mb": 15.8,
        "contents": [
          "/etc/nginx/nginx.conf",
          "/etc/nginx/conf.d/",
          "/var/lib/nginx/",
          "systemctl status nginx.service"
        ],
        "integrity_verified": true
      },
      "rollback_info": {
        "prepared": true,
        "checkpoints": 4,
        "rollback_plan": {
          "steps": [
            "stop_nginx_service",
            "restore_backup",
            "start_nginx_service",
            "verify_restoration"
          ],
          "estimated_time_seconds": 25
        }
      }
    },
    "performance": {
      "total_duration_seconds": 32.5,
      "phase_breakdown": {
        "initialization": 2.1,
        "safety_control": 3.5,
        "repair_execution": 8.7,
        "verification": 15.2,
        "cleanup": 3.0
      },
      "resource_usage": {
        "cpu_percent": 12.8,
        "memory_mb": 145,
        "disk_io_mb": 38.5
      }
    }
  },
  "metadata": {
    "skill_name": "controlled-repair",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T02:30:32Z",
    "execution_mode": "standard"
  }
}
```

### 关键成功指标

1. **服务中断时间**：< 10秒
2. **备份完整性**：备份文件完整且可恢复
3. **验证通过率**：所有验证检查都通过
4. **资源消耗**：CPU使用率 < 20%，内存使用 < 200MB
5. **执行时间**：总执行时间 < 60秒

## 故障排除

### 常见问题1：权限不足

**症状**：
```json
{
  "status": "error",
  "error_code": "PERMISSION_DENIED",
  "error_message": "执行用户权限不足，无法重启系统服务"
}
```

**解决方法**：
1. 使用sudo执行命令：
   ```bash
   sudo claude witty-diagnosis:controlled-repair --target service --repair-action restart --repair-target nginx.service
   ```
2. 配置sudo权限允许特定用户重启nginx：
   ```bash
   # 编辑sudoers文件
   visudo
   # 添加以下行
   username ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nginx.service
   ```
3. 使用具有适当权限的用户执行

### 常见问题2：服务启动失败

**症状**：
```json
{
  "status": "partial",
  "results": {
    "summary": {
      "verification_passed": false
    },
    "execution_details": {
      "verification": {
        "failed_checks": [
          {
            "name": "service_status",
            "status": "failed",
            "error": "nginx.service: failed"
          }
        ]
      }
    }
  }
}
```

**解决方法**：
1. 检查nginx配置语法：
   ```bash
   nginx -t
   ```
2. 查看nginx错误日志：
   ```bash
   journalctl -u nginx.service --since "5 minutes ago"
   ```
3. 手动修复配置问题后重试
4. 使用回滚功能恢复之前的状态

### 常见问题3：验证超时

**症状**：
```json
{
  "status": "partial",
  "results": {
    "summary": {
      "verification_passed": false
    },
    "execution_details": {
      "verification": {
        "status": "timeout",
        "error": "HTTP响应验证超时"
      }
    }
  }
}
```

**解决方法**：
1. 增加验证超时时间：
   ```bash
   claude witty-diagnosis:controlled-repair ... --verification-interval 10 --verification-attempts 10
   ```
2. 检查网络连接和防火墙设置
3. 验证nginx是否监听正确端口
4. 检查应用是否正常启动

### 常见问题4：备份空间不足

**症状**：
```json
{
  "status": "error",
  "error_code": "BACKUP_FAILED",
  "error_message": "备份创建失败：磁盘空间不足"
}
```

**解决方法**：
1. 清理磁盘空间：
   ```bash
   # 查看磁盘使用情况
   df -h /var/backups

   # 清理旧备份文件
   find /var/backups -name "*.tar.gz" -mtime +7 -delete
   ```
2. 指定其他备份位置：
   ```bash
   claude witty-diagnosis:controlled-repair ... --backup-location "/opt/backups"
   ```
3. 禁用备份（仅用于测试）：
   ```bash
   claude witty-diagnosis:controlled-repair ... --backup-before-repair false
   ```

## 调试技巧

### 1. 启用详细日志
```bash
claude witty-diagnosis:controlled-repair ... --verbosity debug
```

### 2. 模拟执行（dry run）
```bash
claude witty-diagnosis:controlled-repair ... --dry-run true
```

### 3. 分阶段执行
```bash
# 只执行到风险评估阶段
claude witty-diagnosis:controlled-repair ... --stop-after risk-assessment

# 只执行到备份创建阶段
claude witty-diagnosis:controlled-repair ... --stop-after backup
```

### 4. 查看执行日志
```bash
# 查看技能执行日志
tail -f /var/log/witty-diagnosis/controlled-repair.log

# 查看系统日志
journalctl -f -u witty-diagnosis-agent
```

## 最佳实践

### 1. 时间选择
- 在业务低峰期执行服务重启
- 避免在业务高峰期或重要活动期间执行
- 提前通知相关团队和用户

### 2. 备份策略
- 始终启用备份功能
- 定期清理旧备份文件
- 验证备份文件的完整性和可恢复性
- 考虑异地备份重要配置

### 3. 验证策略
- 设计全面的验证测试用例
- 包括功能测试、性能测试和错误检查
- 设置合理的验证超时和重试次数
- 记录验证结果用于后续分析

### 4. 监控告警
- 监控服务重启过程中的关键指标
- 设置服务中断时间告警阈值
- 监控修复后的服务性能指标
- 建立修复操作效果跟踪机制

### 5. 文档记录
- 记录每次修复操作的详细信息
- 分析修复成功和失败的原因
- 积累修复经验到知识库
- 定期回顾和优化修复流程

## 扩展场景

### 场景1：批量服务重启
当需要重启多个相关服务时：
```bash
# 创建服务列表文件 services.txt
echo "nginx.service" > services.txt
echo "php-fpm.service" >> services.txt
echo "redis.service" >> services.txt

# 批量重启服务
for service in $(cat services.txt); do
  claude witty-diagnosis:controlled-repair \
    --target service \
    --repair-action restart \
    --repair-target "$service" \
    --backup-before-repair true
done
```

### 场景2：依赖服务重启
当服务有依赖关系时，需要按顺序重启：
```bash
# 先重启数据库服务
claude witty-diagnosis:controlled-repair --target service --repair-action restart --repair-target postgresql.service

# 等待数据库就绪后重启应用服务
sleep 30
claude witty-diagnosis:controlled-repair --target service --repair-action restart --repair-target myapp.service
```

### 场景3：蓝绿部署切换
结合配置管理实现蓝绿部署：
```bash
# 停止旧版本服务
claude witty-diagnosis:controlled-repair --target service --repair-action stop --repair-target app-v1.service

# 启动新版本服务
claude witty-diagnosis:controlled-repair --target service --repair-action start --repair-target app-v2.service

# 验证新版本服务
claude witty-diagnosis:controlled-repair --target service --repair-action verify --repair-target app-v2.service
```

---

*示例版本：1.0.0*
*最后更新：2026-02-03*