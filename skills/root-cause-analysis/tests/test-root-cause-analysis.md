# 根因分析技能测试用例

## 概述

本文档包含root-cause-analysis技能的完整测试用例，用于验证技能的功能正确性、性能表现和健壮性。测试用例覆盖正常流程、边界条件、错误处理和性能测试等多个方面。

## 测试环境要求

### 硬件环境
- CPU：4核或以上
- 内存：8GB或以上
- 存储：50GB可用空间
- 网络：稳定网络连接

### 软件环境
- 操作系统：欧拉OS 2.0或兼容Linux发行版
- Python：3.8或以上
- 依赖库：numpy, scipy, pandas, scikit-learn, networkx
- 数据库：MySQL 8.0或PostgreSQL 12（用于历史故障数据库）
- 测试工具：pytest, unittest

### 测试数据
- 历史故障数据库：包含至少100个历史故障案例
- 测试数据集：预定义的故障场景数据
- 模拟数据生成器：用于生成测试数据

## 测试用例分类

### 1. 功能测试
验证技能核心功能的正确性

### 2. 性能测试
验证技能的性能表现和资源使用

### 3. 健壮性测试
验证技能在异常条件下的行为

### 4. 集成测试
验证技能与其他技能的集成

## 详细测试用例

### 测试用例1：基础功能测试 - 内存泄漏根因分析

#### 测试目的
验证技能对典型内存泄漏故障的根因分析能力

#### 测试环境
- 历史数据库：包含内存泄漏相关案例
- 测试数据：模拟的内存泄漏故障数据
- 算法配置：使用贝叶斯网络和决策树算法

#### 测试步骤
1. 准备测试输入数据（内存泄漏场景）
2. 执行根因分析技能
3. 验证输出结果
4. 检查分析过程日志

#### 输入数据
```json
{
  "session_id": "test-memory-leak-001",
  "target": "system",
  "fault_data": {
    "issues": [
      {
        "id": "test-mem-001",
        "type": "performance_degradation",
        "severity": "high",
        "description": "内存使用率持续增长",
        "symptoms": ["high_memory_usage", "frequent_gc", "slow_response"],
        "possible_causes": ["memory_leak", "cache_misconfiguration", "application_bug"],
        "evidence": {
          "metrics": {
            "memory_usage_percent": 92.5,
            "gc_frequency": 15,
            "response_time_ms": 450
          },
          "logs": [
            {
              "timestamp": "2026-02-03T10:00:00Z",
              "level": "WARNING",
              "message": "High memory usage detected"
            }
          ]
        }
      }
    ]
  },
  "parameters": {
    "analysis_algorithms": ["bayesian", "decision_tree"],
    "confidence_threshold": 0.7
  }
}
```

#### 预期输出
- 状态：success
- 主要根因：memory_leak
- 置信度：> 0.7
- 包含因果关系链
- 包含修复建议

#### 验证点
- [ ] 正确识别内存泄漏为根本原因
- [ ] 置信度高于阈值
- [ ] 因果关系链合理
- [ ] 修复建议具体可行
- [ ] 执行时间 < 30秒

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
基础功能测试，验证核心分析能力

---

### 测试用例2：多算法一致性测试

#### 测试目的
验证不同算法对同一故障的分析结果一致性

#### 测试环境
- 测试数据：标准故障场景
- 算法配置：启用所有可用算法

#### 测试步骤
1. 准备标准测试数据
2. 执行包含所有算法的根因分析
3. 比较各算法结果
4. 验证结果整合逻辑

#### 输入数据
```json
{
  "session_id": "test-algorithm-consistency-001",
  "target": "system",
  "fault_data": {
    "issues": [
      {
        "id": "test-alg-001",
        "type": "disk_issue",
        "description": "磁盘空间不足",
        "symptoms": ["high_disk_usage", "slow_io"],
        "possible_causes": ["log_accumulation", "temp_files", "backup_files"],
        "evidence": {
          "metrics": {
            "disk_usage_percent": 95.2,
            "io_wait_percent": 45.3
          }
        }
      }
    ]
  },
  "parameters": {
    "analysis_algorithms": ["bayesian", "decision_tree", "causal_graph", "historical_matching"],
    "confidence_threshold": 0.6
  }
}
```

#### 预期输出
- 状态：success
- 各算法结果基本一致
- 最终根因明确
- 算法间置信度差异 < 0.2

#### 验证点
- [ ] 所有算法成功执行
- [ ] 算法结果基本一致
- [ ] 结果整合逻辑正确
- [ ] 冲突解决机制有效
- [ ] 执行时间 < 60秒

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
验证多算法协同工作的正确性

---

### 测试用例3：历史模式匹配测试

#### 测试目的
验证历史故障模式匹配功能的准确性

#### 测试环境
- 历史数据库：包含相关故障模式
- 测试数据：与历史案例相似的故障

#### 测试步骤
1. 准备与历史案例相似的测试数据
2. 启用历史模式匹配
3. 执行根因分析
4. 验证匹配结果

#### 输入数据
```json
{
  "session_id": "test-historical-matching-001",
  "target": "network",
  "fault_data": {
    "issues": [
      {
        "id": "test-hist-001",
        "type": "network_latency",
        "description": "网络延迟增加",
        "symptoms": ["high_latency", "packet_loss"],
        "possible_causes": ["network_congestion", "router_issue", "firewall"],
        "evidence": {
          "metrics": {
            "latency_ms": 250,
            "packet_loss_percent": 8.5
          }
        }
      }
    ]
  },
  "parameters": {
    "analysis_algorithms": ["historical_matching"],
    "use_historical_data": true,
    "confidence_threshold": 0.65
  }
}
```

#### 预期输出
- 状态：success
- 匹配到相似历史案例
- 相似度分数 > 0.7
- 历史根因被正确引用

#### 验证点
- [ ] 成功连接到历史数据库
- [ ] 正确匹配到相似案例
- [ ] 相似度计算合理
- [ ] 历史根因影响最终结果
- [ ] 执行时间 < 45秒

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
验证历史数据利用能力

---

### 测试用例4：低置信度场景测试

#### 测试目的
验证在证据不足时的正确处理

#### 测试环境
- 测试数据：证据不足的故障场景
- 算法配置：标准算法

#### 测试步骤
1. 准备证据不足的测试数据
2. 执行根因分析
3. 验证低置信度处理
4. 检查警告信息

#### 输入数据
```json
{
  "session_id": "test-low-confidence-001",
  "target": "system",
  "fault_data": {
    "issues": [
      {
        "id": "test-low-001",
        "type": "performance_issue",
        "description": "性能下降原因不明",
        "symptoms": ["slow_response"],
        "possible_causes": ["cpu", "memory", "disk", "network"],
        "evidence": {
          "metrics": {
            "response_time_ms": 300
          }
        }
      }
    ]
  },
  "parameters": {
    "analysis_algorithms": ["bayesian", "decision_tree"],
    "confidence_threshold": 0.7
  }
}
```

#### 预期输出
- 状态：success 或 partial
- 根因置信度 < 0.7
- 包含低置信度警告
- 建议收集更多证据

#### 验证点
- [ ] 正确识别证据不足
- [ ] 置信度分数反映证据强度
- [ ] 提供明确的警告信息
- [ ] 建议具体可行
- [ ] 不产生误导性结果

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
验证技能在不确定性下的稳健性

---

### 测试用例5：复杂多故障场景测试

#### 测试目的
验证处理多个相关故障的能力

#### 测试环境
- 测试数据：包含多个相关故障
- 算法配置：支持复杂分析

#### 测试步骤
1. 准备多故障测试数据
2. 执行根因分析
3. 验证多故障处理
4. 检查共同根因识别

#### 输入数据
```json
{
  "session_id": "test-multi-fault-001",
  "target": "system",
  "fault_data": {
    "issues": [
      {
        "id": "test-multi-001",
        "type": "cpu_issue",
        "description": "CPU使用率过高",
        "symptoms": ["high_cpu_usage"],
        "possible_causes": ["compute_intensive_task", "deadlock", "configuration"],
        "evidence": {
          "metrics": {
            "cpu_usage_percent": 95.2
          }
        }
      },
      {
        "id": "test-multi-002",
        "type": "memory_issue",
        "description": "内存使用率过高",
        "symptoms": ["high_memory_usage"],
        "possible_causes": ["memory_leak", "cache_issue"],
        "evidence": {
          "metrics": {
            "memory_usage_percent": 88.5
          }
        }
      }
    ],
    "context": {
      "system_info": {
        "hostname": "test-server-01"
      }
    }
  },
  "parameters": {
    "analysis_algorithms": ["causal_graph", "bayesian"],
    "confidence_threshold": 0.7
  }
}
```

#### 预期输出
- 状态：success
- 识别共同根因或独立根因
- 因果关系覆盖所有故障
- 修复建议针对所有故障

#### 验证点
- [ ] 正确处理多个故障
- [ ] 识别故障间关联
- [ ] 因果关系分析完整
- [ ] 修复建议全面
- [ ] 执行时间 < 90秒

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
验证复杂场景处理能力

---

### 测试用例6：输入验证测试 - 无效数据

#### 测试目的
验证对无效输入数据的错误处理

#### 测试环境
- 测试数据：格式错误或缺失必需字段
- 预期行为：优雅失败并提供有用错误信息

#### 测试步骤
1. 准备无效输入数据
2. 执行根因分析
3. 验证错误处理
4. 检查错误信息质量

#### 输入数据
```json
{
  "session_id": "test-invalid-input-001",
  "target": "system"
  // 缺少必需的fault_data字段
}
```

#### 预期输出
- 状态：error
- 错误代码：VALIDATION_INPUT_INVALID
- 清晰的错误信息
- 具体的修复建议

#### 验证点
- [ ] 正确识别输入错误
- [ ] 错误信息清晰明确
- [ ] 提供具体修复建议
- [ ] 不泄露敏感信息
- [ ] 执行时间 < 5秒

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
验证输入验证和错误处理

---

### 测试用例7：性能测试 - 大数据量分析

#### 测试目的
验证处理大数据量时的性能表现

#### 测试环境
- 测试数据：包含大量证据和日志
- 性能要求：在规定时间内完成

#### 测试步骤
1. 准备大数据量测试数据
2. 执行根因分析
3. 监控资源使用
4. 验证性能指标

#### 输入数据
```json
{
  "session_id": "test-performance-001",
  "target": "system",
  "fault_data": {
    "issues": [
      {
        "id": "test-perf-001",
        "type": "log_analysis",
        "description": "大量错误日志分析",
        "symptoms": ["error_logs"],
        "possible_causes": ["application_bug", "configuration", "resource"],
        "evidence": {
          "logs": [
            // 包含1000条模拟日志条目
          ]
        }
      }
    ]
  },
  "parameters": {
    "analysis_algorithms": ["decision_tree", "historical_matching"],
    "timeout": 120
  }
}
```

#### 预期输出
- 状态：success
- 在规定时间内完成
- 内存使用 < 2GB
- CPU使用合理

#### 验证点
- [ ] 在规定时间内完成（< 120秒）
- [ ] 内存使用在限制范围内
- [ ] CPU使用合理
- [ ] 不出现内存泄漏
- [ ] 输出数据大小可控

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
验证性能表现和资源管理

---

### 测试用例8：边界条件测试 - 最小输入

#### 测试目的
验证在最小有效输入下的行为

#### 测试环境
- 测试数据：仅包含必需字段
- 预期行为：正常执行但置信度可能较低

#### 测试步骤
1. 准备最小有效输入
2. 执行根因分析
3. 验证基本功能
4. 检查结果合理性

#### 输入数据
```json
{
  "session_id": "test-minimal-001",
  "target": "system",
  "fault_data": {
    "issues": [
      {
        "id": "test-min-001",
        "type": "generic",
        "description": "一般故障",
        "symptoms": ["symptom"],
        "possible_causes": ["cause1", "cause2"]
      }
    ]
  }
}
```

#### 预期输出
- 状态：success 或 partial
- 基本功能正常
- 可能低置信度
- 合理的结果

#### 验证点
- [ ] 接受最小有效输入
- [ ] 基本功能正常
- [ ] 结果合理
- [ ] 不崩溃或异常
- [ ] 执行时间 < 20秒

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
验证边界条件处理

---

### 测试用例9：算法参数调优测试

#### 测试目的
验证算法参数调整对结果的影响

#### 测试环境
- 测试数据：标准故障场景
- 参数配置：不同参数组合

#### 测试步骤
1. 准备标准测试数据
2. 使用不同参数执行多次分析
3. 比较结果差异
4. 验证参数影响

#### 输入数据
```json
{
  "session_id": "test-params-001",
  "target": "system",
  "fault_data": {
    "issues": [
      {
        "id": "test-params-001",
        "type": "test_scenario",
        "description": "测试场景",
        "symptoms": ["symptom1", "symptom2"],
        "possible_causes": ["cause_a", "cause_b", "cause_c"],
        "evidence": {
          "metrics": {
            "metric1": 75.5,
            "metric2": 60.2
          }
        }
      }
    ]
  }
}
```

#### 测试参数组合
1. confidence_threshold: 0.5, 0.7, 0.9
2. max_hypotheses: 3, 5, 10
3. 算法组合：不同算法组合

#### 预期输出
- 参数调整影响结果
- 阈值影响根因确定
- 算法组合影响分析深度

#### 验证点
- [ ] 参数调整有效
- [ ] 阈值影响合理
- [ ] 算法组合工作正常
- [ ] 结果可重现
- [ ] 参数文档准确

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
验证参数调优功能

---

### 测试用例10：集成测试 - 与故障定位技能集成

#### 测试目的
验证与fault-localization技能的集成

#### 测试环境
- 前置技能：fault-localization已执行
- 数据传递：故障定位结果作为输入

#### 测试步骤
1. 执行fault-localization技能
2. 获取故障定位结果
3. 作为输入执行根因分析
4. 验证端到端流程

#### 端到端流程
```bash
# 1. 执行故障定位
claude witty-diagnosis:fault-localization --target system --input monitoring-data.json

# 2. 提取故障数据
FAULT_DATA=$(claude witty-diagnosis:extract --session-id fault-session-001 --output json)

# 3. 执行根因分析
claude witty-diagnosis:root-cause-analysis --session-id rca-session-001 --fault-data "$FAULT_DATA"
```

#### 预期输出
- 端到端流程成功
- 数据格式兼容
- 结果连贯合理

#### 验证点
- [ ] 数据格式兼容
- [ ] 端到端流程成功
- [ ] 结果连贯合理
- [ ] 错误处理一致
- [ ] 性能可接受

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
验证技能间集成

---

### 测试用例11：安全测试 - 权限验证

#### 测试目的
验证权限控制和数据安全

#### 测试环境
- 权限配置：不同权限级别
- 安全要求：数据保护和访问控制

#### 测试步骤
1. 使用不同权限执行
2. 验证权限检查
3. 测试数据访问控制
4. 验证错误处理

#### 测试场景
1. 无历史数据库访问权限
2. 无文件系统访问权限
3. 无网络访问权限

#### 预期输出
- 适当的权限错误
- 优雅降级
- 不泄露敏感信息

#### 验证点
- [ ] 权限检查有效
- [ ] 错误信息适当
- [ ] 不泄露敏感信息
- [ ] 优雅降级处理
- [ ] 审计日志记录

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
验证安全控制

---

### 测试用例12：回归测试 - 历史案例验证

#### 测试目的
验证对历史已知案例的分析准确性

#### 测试环境
- 历史案例：已知根因的故障案例
- 验证方法：对比分析结果与已知根因

#### 测试步骤
1. 选择历史已知案例
2. 执行根因分析
3. 对比分析结果与已知根因
4. 计算准确率

#### 测试数据集
- 案例1：已知内存泄漏案例
- 案例2：已知网络问题案例
- 案例3：已知配置错误案例
- 案例4：已知资源竞争案例

#### 预期输出
- 准确识别已知根因
- 准确率 > 85%
- 置信度合理

#### 验证点
- [ ] 准确识别已知根因
- [ ] 准确率达标
- [ ] 置信度合理
- [ ] 结果稳定
- [ ] 执行时间可接受

#### 测试状态
- [ ] 通过
- [ ] 失败
- [ ] 阻塞

#### 备注
验证分析准确性

## 测试执行计划

### 测试周期
- 每日：执行基础功能测试（测试用例1-3）
- 每周：执行完整测试套件（所有测试用例）
- 每月：执行性能和安全测试（测试用例7,11）
- 发布前：执行完整回归测试

### 测试工具
```bash
# 测试脚本示例
#!/bin/bash

# 设置测试环境
export TEST_ENV=development
export TEST_DATA_DIR=/tmp/test-data

# 执行测试套件
pytest tests/test_basic_functionality.py -v
pytest tests/test_performance.py -v --timeout=300
pytest tests/test_integration.py -v

# 生成测试报告
claude witty-diagnosis:test-report --format html --output /tmp/test-report.html
```

### 测试数据管理
1. **测试数据生成**
   ```python
   # 生成测试数据的Python脚本
   import json
   import random

   def generate_test_data(scenario_type):
       # 根据场景类型生成测试数据
       pass
   ```

2. **测试数据清理**
   ```bash
   # 清理测试数据
   rm -rf /tmp/test-data/*
   rm -f /tmp/test-*.json
   ```

3. **测试结果存储**
   ```bash
   # 存储测试结果
   mkdir -p /var/log/witty-diagnosis/tests
   cp /tmp/test-report.html /var/log/witty-diagnosis/tests/
   ```

## 测试质量指标

### 功能测试指标
- 测试通过率：> 95%
- 功能覆盖率：> 90%
- 缺陷密度：< 0.1 defects/KLOC

### 性能测试指标
- 平均响应时间：< 60秒
- 内存使用：< 2GB
- CPU使用：< 70%
- 并发能力：支持5个并发分析

### 可靠性指标
- 可用性：> 99.5%
- 平均无故障时间：> 720小时
- 恢复时间：< 5分钟

### 安全指标
- 安全漏洞：0 critical, < 3 medium
- 权限控制：100%覆盖
- 数据保护：符合安全标准

## 问题跟踪和修复

### 问题分类
1. **严重问题**：功能完全失效，安全漏洞
2. **主要问题**：主要功能异常，性能严重下降
3. **次要问题**：边缘功能异常，用户体验问题
4. **改进建议**：功能增强，性能优化

### 问题处理流程
1. 发现问题并记录
2. 分配优先级和负责人
3. 分析根本原因
4. 实施修复
5. 验证修复效果
6. 更新测试用例

### 问题跟踪模板
```markdown
## 问题报告

**问题ID**: BUG-001
**发现时间**: 2026-02-03 10:30:00
**测试用例**: 测试用例1
**严重程度**: 主要

**问题描述**:
根因分析技能在处理特定类型的输入数据时返回错误结果。

**重现步骤**:
1. 准备测试数据X
2. 执行技能
3. 观察输出

**预期行为**:
应返回正确根因

**实际行为**:
返回错误根因

**环境信息**:
- 系统: EulerOS 2.0
- Python: 3.8.10
- 技能版本: 1.0.0

**日志信息**:
[相关日志片段]

**根本原因分析**:
[分析结果]

**修复方案**:
[修复描述]

**验证结果**:
[验证结果]
```

## 测试报告模板

### 测试执行摘要
```markdown
## 测试执行报告

**报告日期**: 2026-02-03
**测试周期**: 2026-02-01 至 2026-02-03
**测试人员**: SRE团队

### 执行概况
- 总测试用例数: 12
- 执行测试用例数: 12
- 通过测试用例数: 11
- 失败测试用例数: 1
- 阻塞测试用例数: 0
- 测试通过率: 91.7%

### 详细结果
| 测试用例 | 状态 | 执行时间 | 备注 |
|----------|------|----------|------|
| 测试用例1 | 通过 | 25.3s | - |
| 测试用例2 | 通过 | 42.8s | - |
| ... | ... | ... | ... |
| 测试用例7 | 失败 | 125.8s | 内存使用超标 |

### 性能指标
- 平均响应时间: 45.2s
- 最大内存使用: 1.8GB
- CPU使用率: 65.2%
- 成功率: 95.8%

### 问题汇总
1. BUG-001: 测试用例7内存使用超标
2. IMP-001: 测试用例3执行时间可优化

### 建议和改进
1. 优化内存使用算法
2. 增加缓存机制
3. 完善错误处理

### 结论
技能基本功能正常，性能有待优化，建议在下一个版本中解决发现的问题。
```

## 持续集成

### CI/CD流水线
```yaml
# .github/workflows/test.yml
name: Root Cause Analysis Tests

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v2

    - name: Set up Python
      uses: actions/setup-python@v2
      with:
        python-version: '3.8'

    - name: Install dependencies
      run: |
        pip install -r requirements.txt
        pip install -r requirements-test.txt

    - name: Run tests
      run: |
        pytest tests/ -v --cov=root_cause_analysis --cov-report=xml

    - name: Upload coverage
      uses: codecov/codecov-action@v2

    - name: Generate test report
      run: |
        python generate_test_report.py

    - name: Upload test results
      uses: actions/upload-artifact@v2
      with:
        name: test-results
        path: test-reports/
```

### 质量门禁
1. **测试通过率**: > 90%
2. **代码覆盖率**: > 80%
3. **性能指标**: 符合要求
4. **安全扫描**: 无严重漏洞
5. **代码审查**: 通过

## 附录

### 测试数据生成脚本
```python
# generate_test_data.py
import json
import random
from datetime import datetime, timedelta

def generate_memory_leak_scenario():
    """生成内存泄漏测试场景"""
    scenario = {
        "session_id": f"test-mem-{datetime.now().strftime('%Y%m%d%H%M%S')}",
        "target": "system",
        "fault_data": {
            "issues": [
                {
                    "id": "test-mem-001",
                    "type": "performance_degradation",
                    "severity": random.choice(["low", "medium", "high"]),
                    "description": "内存使用率持续增长",
                    "symptoms": ["high_memory_usage", "frequent_gc", "slow_response"],
                    "possible_causes": ["memory_leak", "cache_misconfiguration", "application_bug"],
                    "evidence": {
                        "metrics": {
                            "memory_usage_percent": random.uniform(85.0, 98.0),
                            "gc_frequency": random.randint(10, 20),
                            "response_time_ms": random.uniform(300.0, 800.0)
                        }
                    }
                }
            ]
        }
    }
    return scenario

# 更多生成函数...
```

### 测试环境配置
```yaml
# test-environment.yaml
test_environment:
  name: "root-cause-analysis-test"
  version: "1.0.0"

  database:
    type: "postgresql"
    host: "localhost"
    port: 5432
    name: "test_fault_db"
    user: "test_user"

  resources:
    memory_limit_mb: 2048
    cpu_limit: 2
    timeout_seconds: 300

  monitoring:
    enabled: true
    metrics_port: 9090
    log_level: "INFO"

  test_data:
    historical_cases: 100
    generated_cases: 50
    real_cases: 10
```

---

*测试文档版本：1.0.0*
*创建日期：2026-02-03*
*最后更新：2026-02-03*