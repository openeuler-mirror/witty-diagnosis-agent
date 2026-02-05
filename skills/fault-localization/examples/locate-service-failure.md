# 使用示例：服务故障定位

## 示例信息

| 项目 | 值 |
|------|-----|
| **示例ID** | `EXAMPLE-FL-001` |
| **关联技能** | `fault-localization` |
| **示例类型** | `基础使用` |
| **难度级别** | `初级` |
| **预计时间** | `15分钟` |
| **创建日期** | `2026-02-03` |
| **最后更新** | `2026-02-03` |

## 场景描述

### 业务背景
某电商平台的订单处理服务突然不可用，导致用户无法下单。运维团队收到告警后，需要快速确定故障影响范围，制定应急措施。

### 技术场景
- 系统架构：微服务架构，包含订单服务、支付服务、库存服务等
- 故障现象：订单服务（order-service）响应超时，健康检查失败
- 环境：生产环境，欧拉OS 2.0
- 时间：业务高峰期

### 用户角色
- 运维工程师
- 值班SRE
- 系统管理员

### 前置知识
- 基本命令行操作
- 了解微服务架构概念
- 熟悉服务发现和监控系统
- 了解故障处理基本流程

## 目标

### 学习目标
通过完成此示例，您将能够：
- 使用fault-localization技能定位服务故障
- 分析故障的影响范围和严重程度
- 识别受影响的相关服务
- 生成修复优先级和建议

### 技能目标
掌握以下技能：
- 配置和执行故障定位分析
- 解读依赖关系分析结果
- 根据影响评估制定应急计划
- 验证分析结果的准确性

### 业务目标
实现以下业务价值：
- 快速恢复用户下单功能
- 最小化业务损失
- 防止故障扩散到其他服务
- 建立可复用的故障处理流程

## 环境准备

### 系统要求
| 要求 | 规格 | 验证方法 |
|------|------|----------|
| 操作系统 | EulerOS 2.0+ | `cat /etc/os-release` |
| witty-diagnosis-agent | 1.0.0+ | `claude --version` |
| 服务发现系统 | Consul 1.10+ | `consul version` |
| 监控系统 | Prometheus 2.30+ | `prometheus --version` |

### 安装和配置

1. **验证witty-diagnosis-agent安装**
   ```bash
   claude --version
   ```

2. **检查服务依赖数据源**
   ```bash
   # 检查Consul服务发现
   curl http://localhost:8500/v1/agent/services

   # 检查Prometheus监控
   curl http://localhost:9090/api/v1/query?query=up
   ```

3. **准备测试数据**
   ```bash
   # 创建测试会话目录
   mkdir -p /tmp/fault-localization-demo
   cd /tmp/fault-localization-demo
   ```

### 数据准备

1. **模拟故障场景数据**
   ```json
   {
     "fault_scenario": "order-service-down",
     "timestamp": "2026-02-03T14:30:00Z",
     "affected_service": "order-service",
     "symptoms": ["health-check-failed", "response-timeout", "error-rate-100%"]
   }
   ```

2. **准备服务依赖映射**
   ```yaml
   # service-dependencies.yaml
   order-service:
     dependencies:
       - payment-service
       - inventory-service
       - user-service
     dependents:
       - api-gateway
       - frontend-service
   ```

## 步骤详解

### 步骤1：准备故障定位输入

**目的：** 创建标准的故障定位输入数据

**操作：**
```bash
cat > order-service-fault.json << 'EOF'
{
  "session_id": "order-service-incident-001",
  "target": "service",
  "fault_source": "order-service",
  "fault_type": "service_down",
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    "depth": 3,
    "include_metrics": true,
    "dependency_source": "auto",
    "severity_threshold": "warning",
    "visualization": true
  },
  "metadata": {
    "request_id": "req-order-001",
    "timestamp": "2026-02-03T14:30:00Z",
    "environment": "production",
    "user": {
      "id": "sre-operator-01",
      "name": "值班SRE",
      "role": "sre"
    },
    "context": {
      "incident_id": "INC-20260203-001",
      "priority": "critical",
      "business_impact": "用户无法下单，直接影响收入",
      "time_of_day": "business_peak"
    }
  }
}
EOF
```

**解释：**
- `session_id`: 唯一标识此次分析会话
- `fault_source`: 指定故障源为order-service
- `depth`: 设置分析深度为3层依赖
- `visualization`: 启用图表生成，便于后续分析

**预期输出：**
```
文件创建成功：order-service-fault.json
```

**验证方法：**
```bash
cat order-service-fault.json | jq '.session_id'
```
预期输出：`"order-service-incident-001"`

### 步骤2：执行故障定位分析

**目的：** 运行fault-localization技能分析故障影响

**操作：**
```bash
claude witty-diagnosis:fault-localization --input-file order-service-fault.json --output-file analysis-result.json
```

**解释：**
- `--input-file`: 指定输入JSON文件
- `--output-file`: 将结果保存到文件，便于后续分析

**预期输出：**
```
开始执行故障定位分析...
会话ID: order-service-incident-001
故障源: order-service
分析深度: 3
开始收集依赖数据...
分析依赖关系...
评估影响范围...
生成可视化图表...
分析完成！执行时间: 42.5秒
结果已保存到: analysis-result.json
```

**验证方法：**
```bash
cat analysis-result.json | jq '.status'
```
预期输出：`"success"`

### 步骤3：分析定位结果

**目的：** 解读故障定位分析结果，制定行动计划

**操作：**
```bash
# 查看总体影响评估
cat analysis-result.json | jq '.results.impact_assessment'

# 查看受影响组件列表
cat analysis-result.json | jq '.results.affected_components[] | {id, impact_severity, recovery_priority, recovery_action}'

# 查看修复建议
cat analysis-result.json | jq '.results.recommendations[] | {priority, action, target}'
```

**解释：**
- 首先查看总体影响评估，了解故障严重程度
- 然后分析具体受影响组件，确定修复优先级
- 最后查看系统生成的修复建议

**预期输出：**
```json
{
  "affected_services": 6,
  "overall_severity": "critical",
  "impact_score": 88,
  "estimated_downtime": "1.5小时",
  "business_impact": "high"
}
```

```json
{
  "id": "api-gateway",
  "impact_severity": "critical",
  "recovery_priority": 1,
  "recovery_action": "路由流量到备用订单服务实例"
}
{
  "id": "payment-service",
  "impact_severity": "high",
  "recovery_priority": 2,
  "recovery_action": "监控支付成功率，准备降级方案"
}
```

**验证方法：**
```bash
# 验证是否有critical级别的受影响组件
cat analysis-result.json | jq '.results.affected_components[] | select(.impact_severity == "critical") | .id'
```

### 步骤4：查看可视化图表

**目的：** 通过图表直观理解故障传播路径

**操作：**
```bash
# 查看生成的图表文件
ls -la /tmp/fault-graph-*.png

# 如果系统支持，可以直接打开图表
# xdg-open /tmp/fault-graph-order-service-incident-001.png  # Linux
# open /tmp/fault-graph-order-service-incident-001.png      # macOS
```

**解释：**
- 依赖关系图：展示服务间的依赖关系
- 影响热力图：显示各组件受影响程度
- 恢复时间线：预估各组件恢复时间

**预期输出：**
```
-rw-r--r-- 1 user group 245760 Feb  3 14:32 /tmp/fault-graph-order-service-incident-001.png
-rw-r--r-- 1 user group 192512 Feb  3 14:32 /tmp/impact-heatmap-order-service-incident-001.png
-rw-r--r-- 1 user group 163840 Feb  3 14:32 /tmp/recovery-timeline-order-service-incident-001.png
```

**验证方法：**
```bash
# 验证图表文件大小（应大于100KB）
ls -lh /tmp/fault-graph-order-service-incident-001.png | awk '{print $5}'
```

### 步骤5：制定应急行动计划

**目的：** 基于分析结果制定具体的应急措施

**操作：**
```bash
# 生成应急行动计划
cat > emergency-action-plan.md << 'EOF'
# 订单服务故障应急行动计划

## 故障概况
- **故障源**: order-service
- **发现时间**: 2026-02-03T14:30:00Z
- **严重程度**: CRITICAL
- **业务影响**: 用户无法下单，直接影响收入

## 影响范围分析
- 直接影响服务: 6个
- 关键路径: api-gateway → order-service → payment-service
- 预估影响时长: 1.5小时

## 立即行动（5分钟内）
1. ✅ 切换api-gateway流量到备用订单服务区域
2. ✅ 通知业务团队故障状态和预计恢复时间
3. 🔄 检查order-service日志，确定故障原因

## 短期修复（30分钟内）
1. 🔄 重启故障的order-service实例
2. 🔄 验证支付服务降级方案就绪
3. 🔄 监控库存服务性能指标

## 长期改进（1周内）
1. 📝 优化订单服务健康检查机制
2. 📝 实施服务熔断和降级策略
3. 📝 完善故障演练和应急预案

## 沟通计划
- 每15分钟更新一次状态
- 关键里程碑通知业务负责人
- 恢复后发送事故报告

## 成功标准
- [ ] 用户下单功能恢复
- [ ] 所有依赖服务状态正常
- [ ] 业务指标恢复到正常水平
- [ ] 根本原因已识别并记录
EOF

cat emergency-action-plan.md
```

**解释：**
- 基于fault-localization的分析结果制定具体行动计划
- 区分立即行动、短期修复和长期改进
- 包含明确的成功标准和沟通计划

**预期输出：**
显示完整的应急行动计划文档

**验证方法：**
```bash
# 验证行动计划包含关键行动项
grep -c "立即行动" emergency-action-plan.md
```

## 完整示例

### 完整命令序列

```bash
# 步骤1：准备输入数据
cat > order-service-fault.json << 'EOF'
{
  "session_id": "order-service-incident-001",
  "target": "service",
  "fault_source": "order-service",
  "fault_type": "service_down",
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    "depth": 3,
    "include_metrics": true,
    "dependency_source": "auto",
    "severity_threshold": "warning",
    "visualization": true
  },
  "metadata": {
    "request_id": "req-order-001",
    "timestamp": "2026-02-03T14:30:00Z",
    "environment": "production",
    "context": {
      "incident_id": "INC-20260203-001",
      "priority": "critical"
    }
  }
}
EOF

# 步骤2：执行故障定位
claude witty-diagnosis:fault-localization --input-file order-service-fault.json --output-file analysis-result.json

# 步骤3：分析结果
echo "=== 总体影响评估 ==="
cat analysis-result.json | jq '.results.impact_assessment'

echo -e "\n=== 受影响组件（按优先级排序）==="
cat analysis-result.json | jq '.results.affected_components[] | select(.recovery_priority <= 3) | {id, impact_severity, recovery_priority, recovery_action}'

echo -e "\n=== 修复建议 ==="
cat analysis-result.json | jq '.results.recommendations[] | {priority, action, target, estimated_time}'

# 步骤4：清理临时文件（可选）
# rm -f order-service-fault.json analysis-result.json
# rm -f /tmp/fault-graph-*.png /tmp/impact-heatmap-*.png /tmp/recovery-timeline-*.png
```

### 完整输入文件

```json
{
  "session_id": "order-service-incident-001",
  "target": "service",
  "fault_source": "order-service",
  "fault_type": "service_down",
  "parameters": {
    "timeout": 300,
    "verbosity": "info",
    "depth": 3,
    "include_metrics": true,
    "dependency_source": "auto",
    "severity_threshold": "warning",
    "visualization": true
  },
  "metadata": {
    "request_id": "req-order-001",
    "timestamp": "2026-02-03T14:30:00Z",
    "environment": "production",
    "user": {
      "id": "sre-operator-01",
      "name": "值班SRE",
      "role": "sre"
    },
    "context": {
      "incident_id": "INC-20260203-001",
      "priority": "critical",
      "business_impact": "用户无法下单，直接影响收入",
      "time_of_day": "business_peak"
    }
  }
}
```

### 完整输出示例

```json
{
  "status": "success",
  "session_id": "order-service-incident-001",
  "execution_time": 42.5,
  "results": {
    "fault_analysis": {
      "source": {
        "id": "order-service",
        "type": "service",
        "status": "down",
        "detected_at": "2026-02-03T14:28:30Z",
        "recovery_estimate": "45分钟"
      },
      "type": "service_down",
      "root_cause_hypothesis": "数据库连接池耗尽导致服务不可用",
      "confidence": 0.80
    },
    "dependency_graph": {
      "total_nodes": 18,
      "total_edges": 32,
      "direct_dependencies": 4,
      "indirect_dependencies": 14,
      "critical_paths": [
        ["api-gateway", "order-service", "payment-service", "bank-gateway"]
      ]
    },
    "impact_assessment": {
      "affected_services": 6,
      "affected_components": 18,
      "business_impact": "high",
      "overall_severity": "critical",
      "impact_score": 88,
      "estimated_downtime": "1.5小时",
      "data_risk": "low"
    },
    "affected_components": [
      {
        "id": "api-gateway",
        "type": "service",
        "dependency_level": 1,
        "impact_severity": "critical",
        "current_status": "degraded",
        "business_importance": "high",
        "recovery_priority": 1,
        "recovery_action": "路由流量到备用订单服务实例",
        "estimated_recovery_time": "5分钟"
      },
      {
        "id": "payment-service",
        "type": "service",
        "dependency_level": 2,
        "impact_severity": "high",
        "current_status": "operational",
        "business_importance": "high",
        "recovery_priority": 2,
        "recovery_action": "监控支付成功率，准备降级方案",
        "estimated_recovery_time": "15分钟"
      },
      {
        "id": "inventory-service",
        "type": "service",
        "dependency_level": 2,
        "impact_severity": "medium",
        "current_status": "operational",
        "business_importance": "medium",
        "recovery_priority": 3,
        "recovery_action": "增加监控频率，检查库存同步",
        "estimated_recovery_time": "30分钟"
      }
    ],
    "recommendations": [
      {
        "priority": "immediate",
        "action": "立即切换api-gateway到备用区域",
        "target": "api-gateway",
        "expected_benefit": "恢复用户访问能力",
        "risk": "low",
        "estimated_time": "5分钟"
      },
      {
        "priority": "short_term",
        "action": "检查并修复order-service数据库连接",
        "target": "order-service",
        "expected_benefit": "恢复订单处理功能",
        "risk": "medium",
        "estimated_time": "30分钟"
      },
      {
        "priority": "long_term",
        "action": "实施订单服务多区域部署",
        "target": "system-architecture",
        "expected_benefit": "提高系统可用性",
        "risk": "low",
        "estimated_time": "2周"
      }
    ]
  },
  "metadata": {
    "skill_name": "fault-localization",
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T14:32:00Z",
    "analysis_depth": 3,
    "dependency_source": "auto",
    "components_analyzed": 25
  }
}
```

## 结果验证

### 验证方法1：影响范围验证

```bash
# 验证受影响服务数量
cat analysis-result.json | jq '.results.impact_assessment.affected_services'

# 验证是否有critical级别的组件
cat analysis-result.json | jq '.results.affected_components[] | select(.impact_severity == "critical") | length'
```

**预期结果：**
```
6
1
```

**结果解释：**
- 有6个服务受到直接影响
- 有1个组件被标记为critical级别，需要立即处理

### 验证方法2：修复建议验证

```bash
# 验证是否有立即行动建议
cat analysis-result.json | jq '.results.recommendations[] | select(.priority == "immediate") | .action'

# 验证建议数量
cat analysis-result.json | jq '.results.recommendations | length'
```

**预期结果：**
```
"立即切换api-gateway到备用区域"
3
```

**结果解释：**
- 有明确的立即行动建议
- 共有3条修复建议，覆盖不同时间范围

### 验证指标

| 指标 | 预期范围 | 实际值 | 状态 |
|------|----------|--------|------|
| 执行时间 | < 60秒 | 42.5秒 | ✅ |
| 受影响服务数 | > 0 | 6 | ✅ |
| Critical级别组件 | ≥ 1 | 1 | ✅ |
| 修复建议数 | ≥ 2 | 3 | ✅ |
| 输出格式 | 符合JSON规范 | 有效JSON | ✅ |

## 故障排除

### 常见问题1：依赖数据获取失败

**症状：**
```
错误：无法获取服务依赖数据
错误代码：DEPENDENCY_DATA_UNAVAILABLE
```

**原因：**
- 服务发现系统不可用
- 网络连接问题
- 权限不足

**解决方案：**
```bash
# 方案1：使用配置文件作为依赖源
# 修改输入文件，设置 dependency_source: "config"
# 并提供依赖配置文件路径

# 方案2：检查服务发现系统
curl http://localhost:8500/v1/agent/self

# 方案3：使用手动模式
# 创建手动依赖文件，在metadata中提供
```

**预防措施：**
- 定期检查服务发现系统健康状态
- 维护备份的依赖配置文件
- 实施依赖数据缓存机制

### 常见问题2：分析时间过长

**症状：**
```
警告：分析时间超过预期
当前已运行：180秒
```

**原因：**
- 系统规模过大
- 依赖深度设置过高
- 网络延迟

**解决方案：**
```bash
# 方案1：减少分析深度
# 修改 depth 参数为 2 或 3

# 方案2：增加超时时间
# 修改 timeout 参数为 600（10分钟）

# 方案3：分阶段分析
# 先分析直接依赖，再分析间接依赖
```

**预防措施：**
- 根据系统规模合理设置depth参数
- 实施分析进度监控
- 优化依赖数据查询性能

### 调试技巧

1. **启用详细日志**
   ```bash
   # 设置 verbosity: "debug"
   claude witty-diagnosis:fault-localization --input-file input.json --verbosity debug
   ```

2. **检查中间状态**
   ```bash
   # 查看临时文件
   ls -la /tmp/fault-localization-*

   # 检查依赖数据缓存
   cat /tmp/fault-localization-cache.json | jq '. | length'
   ```

3. **验证数据流**
   ```bash
   # 验证输入数据格式
   cat input.json | jq empty

   # 验证输出数据格式
   cat output.json | jq '.status'
   ```

## 扩展练习

### 练习1：多层依赖分析

**目标：** 分析更深层次的依赖关系

**任务：**
1. 修改输入文件，设置 `depth: 5`
2. 执行故障定位分析
3. 比较与`depth: 3`的结果差异
4. 分析额外发现的依赖关系

**提示：**
- 注意分析时间可能显著增加
- 关注新发现的关键路径
- 评估额外依赖的实际业务影响

**验证方法：**
```bash
cat result.json | jq '.results.dependency_graph.total_nodes'
```

### 练习2：多故障源分析

**目标：** 分析多个服务同时故障的影响

**任务：**
1. 创建模拟多个服务故障的场景
2. 修改`fault_source`为服务列表
3. 分析复合故障的影响范围
4. 制定综合修复计划

**提示：**
- 考虑故障间的相互影响
- 识别共同的依赖组件
- 优化修复顺序以减少总体影响

**验证方法：**
```bash
cat result.json | jq '.results.impact_assessment.affected_services'
```

## 最佳实践

### 配置最佳实践
1. **合理设置分析深度**：生产环境通常3-4层足够，测试环境可设置2层
2. **启用可视化**：图表有助于团队沟通和决策
3. **配置依赖缓存**：减少重复分析时间，提高响应速度
4. **设置适当的超时**：根据系统规模设置，避免分析中断

### 使用最佳实践
1. **定期执行演练**：在非高峰时段测试故障定位流程
2. **建立分析基线**：记录正常状态下的依赖关系，便于对比
3. **团队协作分析**：多人共同解读结果，减少误判
4. **结合监控告警**：将分析结果与监控系统集成，实现自动化

### 性能最佳实践
1. **分批分析大规模系统**：超过100个服务的系统建议分批次分析
2. **利用缓存结果**：相同故障源的重复分析使用缓存数据
3. **优化数据查询**：并行获取依赖数据，减少IO等待时间
4. **监控资源使用**：分析过程中监控CPU和内存使用情况

### 安全最佳实践
1. **控制数据访问**：依赖数据可能包含敏感信息，需控制访问权限
2. **及时清理临时文件**：分析完成后清理包含系统信息的临时文件
3. **审计分析记录**：记录所有故障定位操作，便于追溯和审计
4. **加密敏感数据**：存储和传输包含敏感信息的分析结果时使用加密

## 相关资源

### 文档链接
- [故障定位技能主文档](../SKILL.md)
- [数据格式规范](../../../docs/standards/data-formats.md)
- [技能接口规范](../../../docs/standards/skill-interfaces.md)
- [欧拉OS服务管理指南](https://docs.openeuler.org)

### 代码示例
- [故障定位输入生成脚本](../../../scripts/generate-fault-input.py)
- [依赖数据提取工具](../../../tools/extract-dependencies.sh)
- [可视化图表生成器](../../../tools/generate-impact-charts.py)

### 工具和脚本
```bash
#!/bin/bash
# 自动化故障定位脚本
# 用法：./auto-fault-localization.sh <service_name> <fault_type>

SERVICE_NAME=$1
FAULT_TYPE=$2
SESSION_ID="auto-$(date +%Y%m%d-%H%M%S)-${SERVICE_NAME}"

cat > /tmp/auto-input.json << EOF
{
  "session_id": "${SESSION_ID}",
  "target": "service",
  "fault_source": "${SERVICE_NAME}",
  "fault_type": "${FAULT_TYPE}",
  "parameters": {
    "timeout": 300,
    "depth": 3,
    "visualization": true
  }
}
EOF

claude witty-diagnosis:fault-localization --input-file /tmp/auto-input.json --output-file /tmp/auto-result.json

echo "分析完成！结果文件：/tmp/auto-result.json"
echo "可视化图表：/tmp/fault-graph-${SESSION_ID}.png"
```

## 总结

### 关键要点
1. **快速定位**：fault-localization技能能在几分钟内完成复杂的依赖分析
2. **全面评估**：不仅分析技术影响，还评估业务影响和恢复优先级
3. **可视化支持**：图表帮助团队快速理解复杂依赖关系
4. ** actionable建议**：提供具体的、可操作的修复建议

### 下一步
1. **实践演练**：在测试环境模拟不同故障场景进行练习
2. **集成监控**：将故障定位与现有监控告警系统集成
3. **团队培训**：组织团队学习故障定位的最佳实践
4. **流程优化**：基于分析结果优化故障应急响应流程

### 反馈和贡献
如果您在使用过程中发现问题或有改进建议，请通过以下方式反馈：
- 提交GitHub Issue
- 参与社区讨论
- 贡献代码或文档改进

我们欢迎所有形式的贡献，共同完善故障定位能力。

---

## 附录

### 附录A：配置参考

```yaml
# fault-localization-config.yaml
defaults:
  timeout: 300
  depth: 3
  verbosity: info
  visualization: true

dependency_sources:
  primary: consul
  fallback: config
  cache_ttl: 3600

severity_mapping:
  critical:
    - service_down
    - data_corruption
  high:
    - performance_degradation
    - high_latency
  medium:
    - configuration_error
    - resource_warning
  low:
    - minor_alert
    - informational

business_impact_weights:
  revenue_critical: 1.0
  customer_facing: 0.8
  internal_service: 0.5
  background_job: 0.3
```

### 附录B：命令参考

| 命令 | 参数 | 描述 | 示例 |
|------|------|------|------|
| `claude witty-diagnosis:fault-localization` | `--input-file` | 指定输入JSON文件 | `--input-file fault.json` |
| | `--output-file` | 指定输出JSON文件 | `--output-file result.json` |
| | `--verbosity` | 设置日志级别 | `--verbosity debug` |
| | `--dry-run` | 模拟执行，不实际分析 | `--dry-run` |
| `jq` | `.results.affected_components[]` | 提取受影响组件 | `jq '.results.affected_components[]'` |
| | `.results.recommendations` | 提取修复建议 | `jq '.results.recommendations'` |

### 附录C：术语表

| 术语 | 解释 |
|------|------|
| **故障源** | 发生故障的初始组件或服务 |
| **依赖层级** | 组件与故障源之间的依赖距离（直接依赖为1级） |
| **影响严重度** | 故障对组件的影响程度：critical/high/medium/low |
| **恢复优先级** | 修复组件的优先顺序，数字越小优先级越高 |
| **关键路径** | 业务功能依赖的核心服务链 |
| **级联效应** | 故障从一个组件传播到其他组件的现象 |
| **业务影响** | 故障对业务运营的影响程度评估 |

---

*本示例展示了fault-localization技能在真实故障场景中的应用。通过系统化的分析和可视化的结果，运维团队能够快速理解故障影响，制定有效的应急措施，最大程度减少业务损失。*