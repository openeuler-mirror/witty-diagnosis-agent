# 可控修复技能测试用例

## 概述

本文档包含controlled-repair技能的完整测试用例，用于验证技能在各种场景下的正确性、可靠性和安全性。测试覆盖正常流程、边界条件、错误处理和性能等方面。

## 测试环境

### 硬件环境
- CPU: 4核以上
- 内存: 8GB以上
- 磁盘: 50GB可用空间
- 网络: 正常网络连接

### 软件环境
- 操作系统: 欧拉OS 2.0
- 测试工具: witty-diagnosis-agent 1.0.0
- 依赖服务: nginx, mysql, 测试用服务
- 监控工具: systemctl, journalctl, netstat, curl

### 测试数据准备
1. 创建测试用服务配置文件
2. 准备测试用备份文件
3. 设置测试用户和权限
4. 配置测试监控和日志

## 测试用例

### 测试1：正常服务重启测试

#### 测试目的
验证服务重启操作在正常条件下的正确性和可靠性。

#### 测试环境
- 测试服务: nginx (已安装并运行)
- 用户权限: root或具有sudo权限
- 备份目录: /var/backups/witty-diagnosis-test
- 网络条件: 本地回环网络正常

#### 测试步骤
1. **准备阶段**
   ```bash
   # 安装测试用nginx
   yum install -y nginx
   systemctl start nginx
   systemctl enable nginx

   # 创建测试备份目录
   mkdir -p /var/backups/witty-diagnosis-test
   chmod 755 /var/backups/witty-diagnosis-test

   # 创建测试请求文件
   cat > test-restart-request.json << 'EOF'
   {
     "session_id": "test-restart-normal-001",
     "target": "service",
     "repair_action": "restart",
     "repair_target": "nginx.service",
     "parameters": {
       "timeout": 120,
       "verbosity": "info",
       "require_approval": false,
       "auto_rollback": true,
       "verification_interval": 3,
       "verification_attempts": 3,
       "risk_threshold": "low",
       "dry_run": false,
       "backup_before_repair": true,
       "backup_location": "/var/backups/witty-diagnosis-test"
     },
     "metadata": {
       "request_id": "test-req-001",
       "environment": "test",
       "purpose": "normal_restart_test"
     }
   }
   EOF
   ```

2. **执行阶段**
   ```bash
   # 执行服务重启
   claude witty-diagnosis:controlled-repair --input-file test-restart-request.json

   # 记录执行结果
   cp output.json test-restart-result.json
   ```

3. **验证阶段**
   ```bash
   # 验证服务状态
   systemctl is-active nginx.service

   # 验证端口监听
   netstat -tlnp | grep :80

   # 验证HTTP响应
   curl -s -o /dev/null -w "%{http_code}" http://localhost

   # 验证备份文件
   ls -la /var/backups/witty-diagnosis-test/*.tar.gz

   # 验证输出格式
   jq '.status' test-restart-result.json
   jq '.results.summary.verification_passed' test-restart-result.json
   ```

#### 预期结果
- **状态检查**: `status = "success"`
- **服务状态**: nginx服务active (running)
- **端口监听**: 80端口正常监听
- **HTTP响应**: 返回200状态码
- **备份创建**: 备份文件存在且完整
- **验证通过**: `verification_passed = true`
- **执行时间**: 总执行时间 < 60秒
- **服务中断**: 服务中断时间 < 10秒

#### 验证点
1. 服务优雅停止和启动
2. 备份文件创建和验证
3. 回滚计划准备
4. 效果验证全面性
5. 输出格式规范性
6. 资源清理完整性

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
记录测试过程中的观察和问题。

---

### 测试2：配置回滚测试

#### 测试目的
验证配置回滚操作的正确性和完整性。

#### 测试环境
- 测试配置: /etc/nginx/nginx.conf
- 备份文件: 预创建的配置备份
- 用户权限: root或具有sudo权限
- 网络条件: 本地回环网络正常

#### 测试步骤
1. **准备阶段**
   ```bash
   # 创建原始配置备份
   BACKUP_DIR="/var/backups/witty-diagnosis-test/nginx"
   mkdir -p $BACKUP_DIR
   cp /etc/nginx/nginx.conf $BACKUP_DIR/nginx.conf.original

   # 修改配置（制造问题）
   cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
   echo "# 测试配置 - 错误的worker_processes设置" > /etc/nginx/nginx.conf
   echo "worker_processes 100;" >> /etc/nginx/nginx.conf
   echo "events { worker_connections 1024; }" >> /etc/nginx/nginx.conf
   echo "http { include /etc/nginx/mime.types; }" >> /etc/nginx/nginx.conf

   # 创建测试请求文件
   cat > test-rollback-request.json << 'EOF'
   {
     "session_id": "test-rollback-normal-001",
     "target": "config",
     "repair_action": "rollback",
     "repair_target": "/etc/nginx/nginx.conf",
     "parameters": {
       "timeout": 180,
       "verbosity": "info",
       "require_approval": false,
       "auto_rollback": true,
       "verification_interval": 5,
       "verification_attempts": 3,
       "risk_threshold": "medium",
       "dry_run": false,
       "backup_before_repair": true,
       "backup_location": "/var/backups/witty-diagnosis-test",
       "backup_file": "/var/backups/witty-diagnosis-test/nginx/nginx.conf.original"
     },
     "metadata": {
       "request_id": "test-req-002",
       "environment": "test",
       "issue_description": "测试配置回滚 - worker_processes设置错误"
     }
   }
   EOF
   ```

2. **执行阶段**
   ```bash
   # 执行配置回滚
   claude witty-diagnosis:controlled-repair --input-file test-rollback-request.json

   # 记录执行结果
   cp output.json test-rollback-result.json
   ```

3. **验证阶段**
   ```bash
   # 验证配置恢复
   diff /etc/nginx/nginx.conf /var/backups/witty-diagnosis-test/nginx/nginx.conf.original

   # 验证配置语法
   nginx -t

   # 验证服务状态
   systemctl status nginx.service

   # 验证当前配置备份
   ls -la /var/backups/witty-diagnosis-test/*current*.tar.gz

   # 验证输出结果
   jq '.status' test-rollback-result.json
   jq '.results.summary.verification_passed' test-rollback-result.json
   ```

#### 预期结果
- **状态检查**: `status = "success"`
- **配置恢复**: 配置恢复到原始状态
- **语法检查**: nginx配置语法正确
- **服务状态**: nginx服务正常运行
- **备份验证**: 当前配置备份已创建
- **验证通过**: `verification_passed = true`
- **执行时间**: 总执行时间 < 90秒

#### 验证点
1. 备份文件查找和验证
2. 当前配置备份创建
3. 配置恢复正确性
4. 配置语法验证
5. 服务重载验证
6. 回滚计划完整性

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
记录配置差异和恢复情况。

---

### 测试3：权限不足错误处理测试

#### 测试目的
验证权限不足时的优雅错误处理和建议提供。

#### 测试环境
- 测试服务: nginx (已安装并运行)
- 用户权限: 非特权测试用户
- 备份目录: /var/backups/witty-diagnosis-test
- 权限设置: 测试用户无服务管理权限

#### 测试步骤
1. **准备阶段**
   ```bash
   # 创建测试用户
   useradd -m testuser

   # 切换到测试用户环境
   su - testuser << 'EOF'
   # 创建测试请求文件
   cat > test-permission-request.json << 'INNER'
   {
     "session_id": "test-permission-error-001",
     "target": "service",
     "repair_action": "restart",
     "repair_target": "nginx.service",
     "parameters": {
       "timeout": 60,
       "verbosity": "info",
       "require_approval": false,
       "auto_rollback": true,
       "dry_run": false
     },
     "metadata": {
       "request_id": "test-req-003",
       "environment": "test",
       "purpose": "permission_error_test"
     }
   }
   INNER

   # 执行修复操作（预期失败）
   claude witty-diagnosis:controlled-repair --input-file test-permission-request.json 2>&1 | tee test-permission-output.txt
   EOF

   # 恢复环境
   userdel -r testuser
   ```

2. **验证阶段**
   ```bash
   # 检查输出文件
   cat test-permission-output.txt

   # 解析JSON输出
   grep -A50 '"status": "error"' test-permission-output.txt | head -20

   # 验证错误信息
   grep -q "PERMISSION_DENIED" test-permission-output.txt && echo "权限错误代码正确"
   grep -q "权限不足" test-permission-output.txt && echo "中文错误信息正确"
   grep -q "建议" test-permission-output.txt && echo "修复建议提供正确"

   # 验证服务状态未改变
   systemctl status nginx.service | grep -q "active (running)" && echo "服务状态未受影响"
   ```

#### 预期结果
- **状态检查**: `status = "error"`
- **错误代码**: `error_code = "PERMISSION_DENIED"` 或类似
- **错误信息**: 包含"权限不足"等人类可读描述
- **修复建议**: 提供具体的权限修复建议
- **服务状态**: nginx服务状态未改变
- **资源清理**: 临时资源已清理
- **回滚状态**: 回滚未执行（操作未开始）

#### 验证点
1. 权限检查准确性
2. 错误信息清晰度
3. 修复建议实用性
4. 服务状态保护
5. 资源清理完整性
6. 用户体验友好性

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
记录错误处理的具体表现。

---

### 测试4：高风险操作审批测试

#### 测试目的
验证高风险操作的审批流程和安全性。

#### 测试环境
- 测试操作: 生产环境模拟服务重启
- 审批设置: 启用审批流程
- 用户权限: 具有审批权限的管理员
- 风险等级: 高风险操作

#### 测试步骤
1. **准备阶段**
   ```bash
   # 创建高风险操作请求
   cat > test-approval-request.json << 'EOF'
   {
     "session_id": "test-approval-highrisk-001",
     "target": "service",
     "repair_action": "restart",
     "repair_target": "nginx.service",
     "parameters": {
       "timeout": 180,
       "verbosity": "info",
       "require_approval": true,
       "auto_rollback": true,
       "risk_threshold": "high",
       "dry_run": false,
       "backup_before_repair": true
     },
     "metadata": {
       "request_id": "test-req-004",
       "environment": "production",
       "time_window": "peak",
       "risk_factors": ["业务高峰期", "关键服务", "无冗余"]
     }
   }
   EOF

   # 执行操作（预期等待审批）
   claude witty-diagnosis:controlled-repair --input-file test-approval-request.json --async &
   PID=$!

   # 等待操作进入审批状态
   sleep 5
   ```

2. **审批阶段**
   ```bash
   # 查看待审批操作
   claude witty-diagnosis:controlled-repair --list-pending-approvals

   # 批准操作
   claude witty-diagnosis:controlled-repair --approve-operation test-approval-highrisk-001 --approver "admin" --approval-reason "测试审批流程"

   # 等待操作完成
   wait $PID
   cp output.json test-approval-result.json
   ```

3. **验证阶段**
   ```bash
   # 验证审批记录
   jq '.results.summary.approval_required' test-approval-result.json
   jq '.results.summary.approval_granted' test-approval-result.json
   jq '.results.summary.approver' test-approval-result.json

   # 验证风险评估
   jq '.results.summary.risk_level' test-approval-result.json
   jq '.results.execution_details.phases.initialization.risk_assessment' test-approval-result.json

   # 验证操作结果
   jq '.status' test-approval-result.json
   systemctl status nginx.service
   ```

#### 预期结果
- **审批触发**: `approval_required = true`
- **审批记录**: `approval_granted = true`, `approver = "admin"`
- **风险评估**: `risk_level = "high"`, 风险评估因素正确
- **操作结果**: `status = "success"`, 服务正常重启
- **审计完整**: 审批时间、审批人、审批原因完整记录
- **安全控制**: 未审批前操作阻塞

#### 验证点
1. 审批流程正确触发
2. 风险评估准确性
3. 审批记录完整性
4. 操作阻塞安全性
5. 审批后执行正确性
6. 审计日志完整性

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
记录审批流程的具体表现和时间。

---

### 测试5：修复失败自动回滚测试

#### 测试目的
验证操作失败时的自动回滚机制和状态恢复。

#### 测试环境
- 测试操作: 会失败的配置更新
- 回滚设置: 启用自动回滚
- 备份状态: 有可用的原始配置备份
- 监控工具: 配置变更监控

#### 测试步骤
1. **准备阶段**
   ```bash
   # 备份原始配置
   cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.original.test

   # 创建会失败的配置更新请求
   cat > test-rollback-failure-request.json << 'EOF'
   {
     "session_id": "test-rollback-failure-001",
     "target": "config",
     "repair_action": "reconfigure",
     "repair_target": "/etc/nginx/nginx.conf",
     "parameters": {
       "timeout": 120,
       "verbosity": "info",
       "require_approval": false,
       "auto_rollback": true,
       "rollback_timeout": 60,
       "verification_interval": 5,
       "verification_attempts": 3,
       "risk_threshold": "medium",
       "dry_run": false,
       "backup_before_repair": true,
       "new_config_content": "worker_processes invalid_value;\nevents { worker_connections 1024; }\nhttp { invalid_directive test; }"
     },
     "metadata": {
       "request_id": "test-req-005",
       "environment": "test",
       "purpose": "failure_rollback_test"
     }
   }
   EOF
   ```

2. **执行阶段**
   ```bash
   # 执行会失败的操作
   claude witty-diagnosis:controlled-repair --input-file test-rollback-failure-request.json
   cp output.json test-rollback-failure-result.json
   ```

3. **验证阶段**
   ```bash
   # 验证操作状态
   jq '.status' test-rollback-failure-result.json

   # 验证回滚执行
   jq '.results.partial_results.rollback_executed' test-rollback-failure-result.json
   jq '.results.partial_results.original_state_restored' test-rollback-failure-result.json

   # 验证配置恢复
   diff /etc/nginx/nginx.conf /etc/nginx/nginx.conf.original.test

   # 验证服务状态
   systemctl status nginx.service
   nginx -t

   # 验证错误信息
   jq '.error_code' test-rollback-failure-result.json
   jq '.error_message' test-rollback-failure-result.json
   jq '.details.failed_step' test-rollback-failure-result.json
   ```

#### 预期结果
- **操作状态**: `status = "partial"` 或 `"error"`
- **回滚执行**: `rollback_executed = true`
- **状态恢复**: `original_state_restored = true`
- **配置一致**: 配置恢复到原始状态
- **服务正常**: nginx服务正常运行
- **错误明确**: 错误信息明确指示失败原因
- **建议有用**: 提供具体的修复建议

#### 验证点
1. 失败检测及时性
2. 回滚触发正确性
3. 状态恢复完整性
4. 错误信息清晰度
5. 资源清理彻底性
6. 用户体验友好性

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
记录失败原因和回滚效果。

---

### 测试6：边界条件测试

#### 测试目的
验证技能在边界条件下的健壮性和处理能力。

#### 测试环境
- 测试条件: 各种边界场景
- 监控工具: 系统资源监控
- 日志记录: 详细执行日志

#### 测试步骤
1. **超短超时测试**
   ```bash
   # 设置极短的超时时间
   claude witty-diagnosis:controlled-repair \
     --target service \
     --repair-action restart \
     --repair-target nginx.service \
     --timeout 5 \
     --verbosity debug

   # 验证超时处理
   grep -q "timeout" output.json && echo "超时处理正确"
   ```

2. **极大验证次数测试**
   ```bash
   # 设置大量验证尝试
   claude witty-diagnosis:controlled-repair \
     --target service \
     --repair-action restart \
     --repair-target nginx.service \
     --verification-attempts 100 \
     --verification-interval 1

   # 验证资源控制
   jq '.results.performance.resource_usage' output.json
   ```

3. **无效目标测试**
   ```bash
   # 使用不存在的服务
   claude witty-diagnosis:controlled-repair \
     --target service \
     --repair-action restart \
     --repair-target "nonexistent.service" \
     --verbosity info

   # 验证错误处理
   grep -q "not found" output.json && echo "目标不存在处理正确"
   ```

4. **空配置测试**
   ```bash
   # 使用空配置内容
   claude witty-diagnosis:controlled-repair \
     --target config \
     --repair-action reconfigure \
     --repair-target "/tmp/test-config.conf" \
     --new-config-content "" \
     --verbosity info

   # 验证空配置处理
   grep -q "empty" output.json && echo "空配置处理正确"
   ```

5. **并发操作测试**
   ```bash
   # 同时执行多个操作
   for i in {1..3}; do
     claude witty-diagnosis:controlled-repair \
       --target service \
       --repair-action status \
       --repair-target nginx.service \
       --session-id "concurrent-test-$i" &
   done

   # 验证并发控制
   wait
   grep -q "locked" *.json && echo "并发控制正确"
   ```

#### 预期结果
- **超时处理**: 优雅超时，清理资源
- **资源控制**: 资源使用在合理范围内
- **错误处理**: 明确的错误信息和恢复建议
- **边界适应**: 正确处理各种边界条件
- **并发安全**: 防止并发操作冲突
- **状态一致**: 操作后系统状态一致

#### 验证点
1. 超时处理机制
2. 资源使用控制
3. 错误边界处理
4. 并发操作安全
5. 状态一致性
6. 用户体验

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
记录各边界条件的处理表现。

---

### 测试7：性能测试

#### 测试目的
验证技能在大规模或复杂场景下的性能表现。

#### 测试环境
- 测试规模: 大规模配置回滚
- 监控工具: top, vmstat, iostat
- 性能基准: 建立性能基线

#### 测试步骤
1. **准备大规模测试数据**
   ```bash
   # 创建大型配置文件
   mkdir -p /tmp/large-config
   for i in {1..100}; do
     cat > "/tmp/large-config/config-$i.conf" << EOF
     # 配置文件 $i
     section_${i} {
       parameter_1 = value_${i}_1
       parameter_2 = value_${i}_2
       parameter_3 = value_${i}_3
       parameter_4 = value_${i}_4
       parameter_5 = value_${i}_5
     }
     EOF
   done

   # 创建备份
   tar -czf /var/backups/witty-diagnosis-test/large-config-backup.tar.gz -C /tmp large-config
   ```

2. **执行性能测试**
   ```bash
   # 监控开始
   top -b -d 1 -n 60 > top.log &
   TOP_PID=$!
   vmstat 1 60 > vmstat.log &
   VMSTAT_PID=$!

   # 执行大规模回滚
   START_TIME=$(date +%s)
   claude witty-diagnosis:controlled-repair \
     --target config \
     --repair-action rollback \
     --repair-target "/tmp/large-config" \
     --backup-file "/var/backups/witty-diagnosis-test/large-config-backup.tar.gz" \
     --verbosity info \
     --timeout 300
   END_TIME=$(date +%s)

   # 停止监控
   kill $TOP_PID $VMSTAT_PID
   ```

3. **分析性能数据**
   ```bash
   # 计算执行时间
   DURATION=$((END_TIME - START_TIME))
   echo "总执行时间: $DURATION 秒"

   # 分析资源使用
   grep "Cpu(s)" top.log | tail -10
   grep "memory" vmstat.log | tail -10

   # 验证结果
   jq '.status' output.json
   jq '.execution_time' output.json
   jq '.results.performance' output.json

   # 验证数据完整性
   find /tmp/large-config -type f | wc -l
   ```

#### 预期结果
- **执行时间**: 总时间 < 300秒
- **CPU使用**: 平均CPU使用率 < 50%
- **内存使用**: 峰值内存使用 < 500MB
- **磁盘IO**: IO操作在合理范围内
- **结果正确**: `status = "success"`
- **数据完整**: 所有配置文件正确恢复
- **性能稳定**: 无内存泄漏或资源累积

#### 验证点
1. 执行时间性能
2. CPU资源使用
3. 内存资源使用
4. 磁盘IO性能
5. 结果正确性
6. 资源释放完整性

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
记录性能数据和优化建议。

---

### 测试8：集成测试

#### 测试目的
验证技能与其他技能的集成和协作能力。

#### 测试环境
- 集成技能: data-collector, root-cause-analysis
- 测试流程: 完整的诊断修复流程
- 数据流: 技能间数据传递

#### 测试步骤
1. **数据收集阶段**
   ```bash
   # 收集系统状态数据
   claude witty-diagnosis:data-collector \
     --target system \
     --session-id "integration-test-001" \
     --data-sources logs metrics processes \
     --output-file system-data.json
   ```

2. **根因分析阶段**
   ```bash
   # 分析收集的数据
   claude witty-diagnosis:root-cause-analysis \
     --input-data system-data.json \
     --session-id "integration-test-001" \
     --analysis-type performance \
     --output-file analysis-result.json
   ```

3. **修复执行阶段**
   ```bash
   # 基于分析结果执行修复
   ANALYSIS_RESULT=$(jq -r '.results.recommended_action' analysis-result.json)

   if [[ "$ANALYSIS_RESULT" == *"restart"* ]]; then
     claude witty-diagnosis:controlled-repair \
       --target service \
       --repair-action restart \
       --repair-target "nginx.service" \
       --session-id "integration-test-001" \
       --input-metadata analysis-result.json \
       --output-file repair-result.json
   fi
   ```

4. **验证集成结果**
   ```bash
   # 验证数据流
   jq '.metadata.parent_session' repair-result.json
   jq '.metadata.diagnosis_reference' repair-result.json

   # 验证修复效果
   jq '.status' repair-result.json
   systemctl status nginx.service

   # 验证知识记录
   claude witty-diagnosis:knowledge-base --query "integration-test-001"
   ```

#### 预期结果
- **数据流完整**: 会话ID一致，数据引用正确
- **流程连贯**: 各阶段顺利衔接
- **结果正确**: 修复操作成功执行
- **知识积累**: 经验记录到知识库
- **审计完整**: 完整流程审计记录
- **性能可接受**: 集成流程时间合理

#### 验证点
1. 数据传递正确性
2. 流程衔接顺畅性
3. 结果一致性
4. 知识积累完整性
5. 审计记录全面性
6. 用户体验连贯性

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
记录集成流程的表现和改进点。

## 测试总结

### 测试覆盖率
- 功能测试: 100%覆盖核心功能
- 边界测试: 覆盖主要边界条件
- 错误测试: 覆盖常见错误场景
- 性能测试: 覆盖典型性能场景
- 集成测试: 覆盖主要集成场景

### 测试结果统计
| 测试用例 | 状态 | 执行时间 | 资源使用 | 问题记录 |
|----------|------|----------|----------|----------|
| 测试1 | 待执行 | - | - | - |
| 测试2 | 待执行 | - | - | - |
| 测试3 | 待执行 | - | - | - |
| 测试4 | 待执行 | - | - | - |
| 测试5 | 待执行 | - | - | - |
| 测试6 | 待执行 | - | - | - |
| 测试7 | 待执行 | - | - | - |
| 测试8 | 待执行 | - | - | - |

### 问题跟踪
| 问题ID | 描述 | 严重程度 | 状态 | 解决方案 |
|--------|------|----------|------|----------|
| - | - | - | - | - |

### 改进建议
1. 性能优化建议
2. 用户体验改进
3. 错误处理增强
4. 测试覆盖扩展
5. 文档完善建议

## 附录

### 测试工具脚本
```bash
#!/bin/bash
# 自动化测试脚本

run_test() {
  local test_name=$1
  local test_script=$2

  echo "开始测试: $test_name"
  echo "======================"

  # 执行测试脚本
  bash -c "$test_script"

  local exit_code=$?
  if [ $exit_code -eq 0 ]; then
    echo "测试通过: $test_name"
    return 0
  else
    echo "测试失败: $test_name (退出码: $exit_code)"
    return 1
  fi
}

# 运行所有测试
TESTS=(
  "测试1:正常服务重启测试:test_script_1"
  "测试2:配置回滚测试:test_script_2"
  "测试3:权限不足测试:test_script_3"
  "测试4:审批流程测试:test_script_4"
)

for test_info in "${TESTS[@]}"; do
  IFS=':' read -r test_num test_name test_script <<< "$test_info"
  run_test "$test_name" "$test_script"
done
```

### 测试数据模板
```json
{
  "test_template": {
    "session_id": "test-{TEST_ID}-{TIMESTAMP}",
    "target": "{TARGET_TYPE}",
    "repair_action": "{ACTION_TYPE}",
    "repair_target": "{TARGET_SPECIFIC}",
    "parameters": {
      "timeout": {TIMEOUT},
      "verbosity": "{VERBOSITY_LEVEL}",
      "require_approval": {REQUIRE_APPROVAL},
      "auto_rollback": {AUTO_ROLLBACK}
    },
    "metadata": {
      "request_id": "test-req-{REQUEST_ID}",
      "environment": "{ENVIRONMENT}",
      "purpose": "{TEST_PURPOSE}"
    }
  }
}
```

### 性能基准指标
| 指标 | 优秀 | 良好 | 及格 | 单位 |
|------|------|------|------|------|
| 服务重启时间 | < 5 | < 10 | < 15 | 秒 |
| 配置回滚时间 | < 10 | < 20 | < 30 | 秒 |
| CPU使用率 | < 20% | < 40% | < 60% | % |
| 内存使用 | < 100MB | < 200MB | < 500MB | MB |
| 磁盘IO | < 50MB | < 100MB | < 200MB | MB |
| 网络延迟 | < 50ms | < 100ms | < 200ms | ms |

---

*测试文档版本：1.0.0*
*最后更新：2026-02-03*