# 配置回滚示例

## 场景描述

本示例演示如何使用controlled-repair技能执行配置回滚操作。当配置更新导致系统问题时，快速、安全地回滚到之前的稳定配置是关键的修复操作。

**场景特点**：
- MySQL数据库配置更新后性能下降
- 需要回滚到之前的稳定配置
- 要求验证回滚后的配置正确性
- 需要确保回滚过程不影响现有数据
- 需要完整的审计记录

## 前置条件

### 系统要求
- 欧拉OS 2.0或更高版本
- MySQL数据库已安装并运行
- 系统具有备份和恢复配置的权限
- 有可用的配置备份文件

### 配置要求
- witty-diagnosis-agent已正确安装和配置
- 用户具有读写MySQL配置文件的权限
- 备份目录包含之前的配置备份
- MySQL服务支持配置热重载

### 数据准备
- 确认当前MySQL配置问题
- 识别可用的配置备份文件
- 准备配置验证测试用例
- 确保有当前配置的备份

## 执行步骤

### 1. 准备修复请求

创建修复请求JSON文件 `rollback-mysql-request.json`：

```json
{
  "session_id": "mysql-rollback-example-001",
  "target": "config",
  "repair_action": "rollback",
  "repair_target": "/etc/mysql/my.cnf",
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    "require_approval": true,
    "auto_rollback": true,
    "rollback_timeout": 120,
    "verification_interval": 10,
    "verification_attempts": 5,
    "risk_threshold": "medium",
    "dry_run": false,
    "backup_before_repair": true,
    "backup_location": "/var/backups/witty-diagnosis/mysql",
    "backup_pattern": "mysql-config-*.tar.gz",
    "backup_count_to_keep": 5
  },
  "metadata": {
    "request_id": "req-mysql-example-001",
    "environment": "production",
    "issue_description": "MySQL配置更新后查询性能下降50%，连接数限制过严",
    "priority": "high",
    "user": {
      "id": "dba",
      "role": "database-admin"
    },
    "current_issue": {
      "symptom": "查询响应时间从平均100ms增加到500ms",
      "time_detected": "2026-02-03T10:30:00Z",
      "config_changed": "2026-02-03T09:00:00Z",
      "changed_parameters": ["max_connections=50", "innodb_buffer_pool_size=2G"]
    }
  }
}
```

### 2. 执行修复操作

使用Claude Code执行配置回滚操作：

```bash
# 方式1：直接使用命令行参数
claude witty-diagnosis:controlled-repair \
  --target config \
  --repair-action rollback \
  --repair-target "/etc/mysql/my.cnf" \
  --timeout 300 \
  --require-approval true \
  --auto-rollback true \
  --verification-interval 10 \
  --verification-attempts 5 \
  --risk-threshold medium \
  --backup-before-repair true \
  --backup-location "/var/backups/witty-diagnosis/mysql" \
  --backup-pattern "mysql-config-*.tar.gz"

# 方式2：使用JSON输入文件
claude witty-diagnosis:controlled-repair --input-file rollback-mysql-request.json
```

### 3. 审批流程（如果require_approval=true）

高风险操作需要人工审批：

```bash
# 查看待审批的操作
claude witty-diagnosis:controlled-repair --list-pending-approvals

# 批准操作（需要审批权限）
claude witty-diagnosis:controlled-repair --approve-operation mysql-rollback-example-001

# 拒绝操作
claude witty-diagnosis:controlled-repair --reject-operation mysql-rollback-example-001 --reason "需要进一步测试"
```

### 4. 监控执行过程

配置回滚操作执行过程中，监控以下关键阶段：

1. **备份查找**：查找最近的可用配置备份
2. **备份验证**：验证备份文件的完整性和可用性
3. **当前配置备份**：备份当前的问题配置
4. **配置恢复**：恢复备份配置到目标位置
5. **配置验证**：验证恢复的配置语法正确性
6. **服务重载**：重新加载MySQL服务配置
7. **效果验证**：验证回滚后的系统表现

### 5. 验证修复结果

回滚完成后，执行以下验证：

```bash
# 验证配置语法
mysqld --verbose --help 2>/dev/null | grep -A5 "Default options"

# 检查MySQL服务状态
systemctl status mysql.service

# 测试数据库连接
mysql -u root -p -e "SELECT 1;"

# 检查关键配置参数
mysql -u root -p -e "SHOW VARIABLES LIKE 'max_connections';"
mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"

# 性能测试
mysql -u root -p -e "SELECT BENCHMARK(1000000, MD5('test'));"
```

## 预期结果

### 成功执行结果

配置回滚操作成功执行后，应获得类似以下输出：

```json
{
  "status": "success",
  "session_id": "mysql-rollback-example-001",
  "execution_time": 85.2,
  "results": {
    "summary": {
      "repair_action": "rollback",
      "repair_target": "/etc/mysql/my.cnf",
      "repair_status": "completed",
      "risk_level": "medium",
      "approval_required": true,
      "approval_granted": true,
      "approver": "admin",
      "approval_time": "2026-02-03T14:30:15Z",
      "backup_created": true,
      "rollback_prepared": true,
      "verification_passed": true,
      "backup_used": "mysql-config-20260202-180000.tar.gz",
      "start_time": "2026-02-03T14:30:00Z",
      "end_time": "2026-02-03T14:31:25Z"
    },
    "execution_details": {
      "phases": {
        "initialization": {
          "status": "completed",
          "permission_check": "passed",
          "risk_assessment": {
            "level": "medium",
            "factors": [
              "生产数据库配置变更",
              "可能影响业务连接",
              "需要服务重启"
            ],
            "mitigations": [
              "有完整备份",
              "在维护窗口执行",
              "有回滚计划"
            ]
          }
        },
        "safety_control": {
          "status": "completed",
          "target_locked": true,
          "pre_checks_passed": true,
          "backup_available": true
        },
        "repair_execution": {
          "status": "completed",
          "steps": [
            {
              "name": "backup_find",
              "status": "completed",
              "result": "backup_found",
              "backup_file": "mysql-config-20260202-180000.tar.gz",
              "backup_time": "2026-02-02T18:00:00Z",
              "backup_size_mb": 4.2,
              "backup_contents": [
                "/etc/mysql/my.cnf",
                "/etc/mysql/conf.d/",
                "mysql_variables_20260202_180000.txt"
              ]
            },
            {
              "name": "backup_verify",
              "status": "completed",
              "result": "backup_valid",
              "integrity_check": "passed",
              "config_syntax_check": "passed"
            },
            {
              "name": "current_config_backup",
              "status": "completed",
              "result": "backup_created",
              "backup_file": "mysql-config-current-20260203-143015.tar.gz",
              "backup_size_mb": 4.5
            },
            {
              "name": "config_restore",
              "status": "completed",
              "result": "config_restored",
              "files_restored": [
                "/etc/mysql/my.cnf",
                "/etc/mysql/conf.d/server.cnf"
              ],
              "restore_time_seconds": 3.2
            },
            {
              "name": "config_validation",
              "status": "completed",
              "result": "config_valid",
              "syntax_check": "passed",
              "key_parameters": {
                "max_connections": "200",
                "innodb_buffer_pool_size": "4G",
                "query_cache_size": "128M"
              }
            },
            {
              "name": "service_reload",
              "status": "completed",
              "result": "service_reloaded",
              "method": "systemctl reload mysql",
              "duration_seconds": 8.5,
              "output": "OK"
            }
          ]
        },
        "verification": {
          "status": "completed",
          "checks": [
            {
              "name": "config_syntax",
              "status": "passed",
              "result": "syntax_ok",
              "details": "mysqld: ready for connections."
            },
            {
              "name": "service_status",
              "status": "passed",
              "result": "active (running)",
              "details": "mysql.service: active (running) since Thu 2026-02-03 14:30:45 UTC"
            },
            {
              "name": "database_connection",
              "status": "passed",
              "result": "connection_ok",
              "response_time_ms": 25,
              "details": "1 row in set (0.02 sec)"
            },
            {
              "name": "configuration_check",
              "status": "passed",
              "parameters": [
                {
                  "name": "max_connections",
                  "expected": "200",
                  "actual": "200",
                  "match": true
                },
                {
                  "name": "innodb_buffer_pool_size",
                  "expected": "4294967296",
                  "actual": "4294967296",
                  "match": true
                }
              ]
            },
            {
              "name": "performance_test",
              "status": "passed",
              "result": "performance_ok",
              "benchmark_time_seconds": 4.8,
              "details": "1000000 iterations completed"
            }
          ]
        }
      },
      "backup_info": {
        "backups_found": 3,
        "backups_considered": [
          {
            "file": "mysql-config-20260202-180000.tar.gz",
            "time": "2026-02-02T18:00:00Z",
            "size_mb": 4.2,
            "selected": true,
            "reason": "最近的成功配置备份"
          },
          {
            "file": "mysql-config-20260201-120000.tar.gz",
            "time": "2026-02-01T12:00:00Z",
            "size_mb": 4.1,
            "selected": false,
            "reason": "较旧的备份"
          }
        ],
        "current_config_backup": {
          "created": true,
          "file": "mysql-config-current-20260203-143015.tar.gz",
          "size_mb": 4.5,
          "location": "/var/backups/witty-diagnosis/mysql"
        }
      },
      "rollback_info": {
        "prepared": true,
        "checkpoints": 5,
        "rollback_plan": {
          "steps": [
            "stop_mysql_service",
            "restore_current_backup",
            "start_mysql_service",
            "verify_restoration",
            "cleanup_temp_files"
          ],
          "estimated_time_seconds": 45,
          "dependencies": ["mysql.service stopped"]
        }
      },
      "config_changes": {
        "parameters_rolled_back": [
          {
            "parameter": "max_connections",
            "from": "50",
            "to": "200",
            "impact": "允许更多并发连接"
          },
          {
            "parameter": "innodb_buffer_pool_size",
            "from": "2147483648",
            "to": "4294967296",
            "impact": "增加缓冲池大小，提高性能"
          }
        ],
        "files_affected": ["/etc/mysql/my.cnf", "/etc/mysql/conf.d/server.cnf"]
      }
    },
    "performance": {
      "total_duration_seconds": 85.2,
      "phase_breakdown": {
        "initialization": 5.2,
        "approval_wait": 15.0,
        "safety_control": 8.5,
        "repair_execution": 32.8,
        "verification": 18.7,
        "cleanup": 5.0
      },
      "resource_usage": {
        "cpu_percent": 18.5,
        "memory_mb": 210,
        "disk_io_mb": 65.2
      }
    }
  },
  "metadata": {
    "skill_name": "controlled-repair",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T14:31:25Z",
    "execution_mode": "standard",
    "approval_workflow": "enabled"
  }
}
```

### 关键成功指标

1. **配置恢复准确性**：所有配置参数正确恢复
2. **服务可用性**：MySQL服务持续可用，无中断
3. **性能恢复**：查询性能恢复到之前水平
4. **备份完整性**：备份文件完整且可恢复
5. **执行时间**：总执行时间 < 120秒

## 故障排除

### 常见问题1：备份文件找不到

**症状**：
```json
{
  "status": "error",
  "error_code": "BACKUP_NOT_FOUND",
  "error_message": "找不到符合条件的配置备份文件"
}
```

**解决方法**：
1. 检查备份目录和文件模式：
   ```bash
   ls -la /var/backups/witty-diagnosis/mysql/
   ```
2. 手动指定备份文件：
   ```bash
   claude witty-diagnosis:controlled-repair ... --backup-file "/path/to/specific/backup.tar.gz"
   ```
3. 从其他位置恢复备份：
   ```bash
   # 复制备份文件到正确位置
   cp /opt/backups/mysql-config-20260202.tar.gz /var/backups/witty-diagnosis/mysql/
   ```
4. 使用最近的系统备份：
   ```bash
   # 查找系统备份中的配置文件
   find /var/backups -name "*my.cnf*" -type f | head -5
   ```

### 常见问题2：配置语法错误

**症状**：
```json
{
  "status": "partial",
  "results": {
    "execution_details": {
      "repair_execution": {
        "steps": [
          {
            "name": "config_validation",
            "status": "failed",
            "error": "配置语法错误：未知参数"
          }
        ]
      }
    }
  }
}
```

**解决方法**：
1. 手动检查配置语法：
   ```bash
   mysqld --defaults-file=/etc/mysql/my.cnf --validate-config
   ```
2. 修复配置语法错误：
   ```bash
   # 备份当前文件
   cp /etc/mysql/my.cnf /etc/mysql/my.cnf.bak

   # 使用编辑器修复
   vi /etc/mysql/my.cnf
   ```
3. 使用配置模板：
   ```bash
   # 使用默认配置
   cp /usr/share/mysql/my-default.cnf /etc/mysql/my.cnf
   ```
4. 分段测试配置：
   ```bash
   # 只测试特定配置段
   mysqld --defaults-file=/etc/mysql/my.cnf --validate-config --verbose
   ```

### 常见问题3：服务重载失败

**症状**：
```json
{
  "status": "partial",
  "results": {
    "execution_details": {
      "repair_execution": {
        "steps": [
          {
            "name": "service_reload",
            "status": "failed",
            "error": "服务重载失败：需要完全重启"
          }
        ]
      }
    }
  }
}
```

**解决方法**：
1. 尝试完全重启服务：
   ```bash
   systemctl restart mysql.service
   ```
2. 检查服务依赖：
   ```bash
   systemctl list-dependencies mysql.service
   ```
3. 查看服务日志：
   ```bash
   journalctl -u mysql.service --since "5 minutes ago" -f
   ```
4. 使用安全模式重启：
   ```bash
   systemctl stop mysql.service
   sleep 5
   systemctl start mysql.service
   ```

### 常见问题4：性能验证失败

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
            "name": "performance_test",
            "status": "failed",
            "error": "性能测试超时"
          }
        ]
      }
    }
  }
}
```

**解决方法**：
1. 调整性能测试参数：
   ```bash
   # 减少测试迭代次数
   claude witty-diagnosis:controlled-repair ... --performance-test-iterations 100000
   ```
2. 检查系统负载：
   ```bash
   top -b -n 1 | head -20
   ```
3. 优化测试查询：
   ```bash
   # 使用更简单的测试查询
   mysql -u root -p -e "SELECT BENCHMARK(10000, SHA1('test'));"
   ```
4. 延长验证超时时间：
   ```bash
   claude witty-diagnosis:controlled-repair ... --verification-timeout 60
   ```

## 调试技巧

### 1. 启用配置调试模式
```bash
claude witty-diagnosis:controlled-repair ... --config-debug true
```

### 2. 查看备份内容
```bash
# 列出备份文件内容
tar -tzf /var/backups/witty-diagnosis/mysql/mysql-config-20260202-180000.tar.gz

# 提取单个文件查看
tar -xzf /var/backups/witty-diagnosis/mysql/mysql-config-20260202-180000.tar.gz etc/mysql/my.cnf -O | head -50
```

### 3. 比较配置差异
```bash
# 比较当前配置和备份配置
diff /etc/mysql/my.cnf <(tar -xzf backup.tar.gz etc/mysql/my.cnf -O)

# 使用专门的比较工具
vimdiff /etc/mysql/my.cnf /tmp/backup-my.cnf
```

### 4. 分步执行回滚
```bash
# 只执行到备份验证
claude witty-diagnosis:controlled-repair ... --stop-after backup-verify

# 只执行到配置恢复
claude witty-diagnosis:controlled-repair ... --stop-after config-restore

# 跳过验证阶段
claude witty-diagnosis:controlled-repair ... --skip-verification
```

## 最佳实践

### 1. 备份管理
- 定期创建配置备份（每日或每次变更前）
- 保留多个历史备份版本（至少7天）
- 验证备份文件的完整性和可恢复性
- 加密敏感配置的备份文件
- 实施备份保留策略，自动清理旧备份

### 2. 变更管理
- 所有配置变更前必须创建备份
- 记录变更原因、时间和责任人
- 测试变更在非生产环境的效果
- 制定回滚计划作为变更的一部分
- 监控变更后的系统表现

### 3. 验证策略
- 设计多层次的验证测试
- 包括功能测试、性能测试和安全测试
- 设置合理的验证超时和重试机制
- 记录验证结果用于审计和分析
- 建立验证失败的处理流程

### 4. 权限控制
- 实施最小权限原则
- 高风险操作需要多人审批
- 记录所有操作的审计日志
- 定期审查操作权限
- 实施操作时间窗口限制

### 5. 文档和知识管理
- 记录每次配置回滚的详细信息
- 分析回滚成功和失败的原因
- 积累配置管理经验到知识库
- 定期回顾和优化回滚流程
- 建立配置最佳实践指南

## 扩展场景

### 场景1：多配置文件回滚
当配置分布在多个文件中时：
```bash
# 创建配置文件列表
cat > config-list.txt << EOF
/etc/mysql/my.cnf
/etc/mysql/conf.d/server.cnf
/etc/mysql/conf.d/replication.cnf
/etc/mysql/conf.d/security.cnf
EOF

# 批量回滚配置文件
while read config_file; do
  claude witty-diagnosis:controlled-repair \
    --target config \
    --repair-action rollback \
    --repair-target "$config_file" \
    --backup-location "/var/backups/witty-diagnosis/mysql"
done < config-list.txt
```

### 场景2：条件回滚
根据条件决定是否回滚：
```bash
# 检查当前配置问题
PROBLEM_SEVERITY=$(check_mysql_problem)

if [ "$PROBLEM_SEVERITY" = "critical" ]; then
  # 立即回滚
  claude witty-diagnosis:controlled-repair --target config --repair-action rollback --repair-target /etc/mysql/my.cnf
elif [ "$PROBLEM_SEVERITY" = "warning" ]; then
  # 分析后再决定
  analyze_config_issue
  # 根据分析结果决定是否回滚
else
  # 监控并记录
  monitor_and_log
fi
```

### 场景3：渐进式回滚
分阶段回滚复杂配置：
```bash
# 第一阶段：回滚核心配置
claude witty-diagnosis:controlled-repair --target config --repair-action rollback --repair-target /etc/mysql/my.cnf --partial-rollback core

# 第二阶段：回滚性能配置
sleep 30
claude witty-diagnosis:controlled-repair --target config --repair-action rollback --repair-target /etc/mysql/conf.d/performance.cnf

# 第三阶段：回滚安全配置
sleep 30
claude witty-diagnosis:controlled-repair --target config --repair-action rollback --repair-target /etc/mysql/conf.d/security.cnf
```

### 场景4：配置对比和选择
从多个备份中选择最佳配置：
```bash
# 列出所有可用备份
BACKUP_FILES=$(find /var/backups/witty-diagnosis/mysql -name "mysql-config-*.tar.gz" | sort -r)

# 分析每个备份的性能指标
for backup in $BACKUP_FILES; do
  echo "分析备份: $backup"
  analyze_backup_performance "$backup"
done

# 选择性能最好的备份进行回滚
BEST_BACKUP=$(select_best_backup)
claude witty-diagnosis:controlled-repair --target config --repair-action rollback --repair-target /etc/mysql/my.cnf --backup-file "$BEST_BACKUP"
```

---

*示例版本：1.0.0*
*最后更新：2026-02-03*