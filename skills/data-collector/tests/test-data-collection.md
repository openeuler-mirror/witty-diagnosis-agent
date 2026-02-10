# 数据收集技能测试用例

## 测试概述

本测试文档验证data-collector技能的功能正确性、性能表现和错误处理能力。测试覆盖日志收集、指标收集、配置收集等核心功能。

## 测试环境要求

### 硬件要求
- 欧拉OS 2.0+系统
- 至少2GB可用内存
- 至少10GB可用磁盘空间

### 软件要求
- witty-diagnosis-agent已安装
- 测试数据文件可用
- 必要的系统权限

### 测试数据
- 样本日志文件：`/tmp/test-logs/`目录下的测试日志
- 模拟指标数据：通过测试工具生成的模拟指标

## 测试用例

### TC-DC-001: 基本日志收集功能

**测试目的**: 验证data-collector能够正确收集系统日志

**前置条件**:
1. 测试日志文件已准备：`/tmp/test-logs/messages.test`
2. 文件包含至少10条测试日志条目

**测试步骤**:
1. 执行日志收集命令：
   ```bash
   claude witty-diagnosis:data-collector \
     --data-sources logs \
     --log-paths /tmp/test-logs/messages.test \
     --time-window "1h" \
     --output-format json \
     --output-file /tmp/test-output-dc-001.json
   ```
2. 验证命令返回状态码为0
3. 检查输出文件存在且非空
4. 验证输出JSON格式正确
5. 确认收集的日志条目数量正确

**预期结果**:
- 命令执行成功
- 输出文件包含正确的日志数据
- JSON格式验证通过
- 日志条目数量匹配源文件

**通过标准**: 所有验证步骤通过

### TC-DC-002: 多源日志收集

**测试目的**: 验证能够同时从多个日志源收集数据

**前置条件**:
1. 准备3个测试日志文件：
   - `/tmp/test-logs/system.log`
   - `/tmp/test-logs/application.log`
   - `/tmp/test-logs/security.log`

**测试步骤**:
1. 执行多源日志收集：
   ```bash
   claude witty-diagnosis:data-collector \
     --data-sources logs \
     --log-paths /tmp/test-logs/system.log:/tmp/test-logs/application.log:/tmp/test-logs/security.log \
     --time-window "2h" \
     --output-file /tmp/test-output-dc-002.json
   ```
2. 验证收集成功
3. 检查输出包含所有3个源的数据
4. 验证每个源的条目数量正确

**预期结果**:
- 成功收集所有3个日志源的数据
- 输出文件包含正确的源标识
- 总条目数为各源条目数之和

**通过标准**: 所有源的数据都正确收集

### TC-DC-003: 指标收集功能

**测试目的**: 验证系统指标收集功能

**前置条件**:
1. 系统监控工具正常运行
2. 系统有可收集的性能指标

**测试步骤**:
1. 执行指标收集：
   ```bash
   claude witty-diagnosis:data-collector \
     --data-sources metrics \
     --metric-types cpu memory \
     --collection-frequency 5 \
     --duration-minutes 2 \
     --output-file /tmp/test-output-dc-003.json
   ```
2. 验证命令执行成功
3. 检查输出文件包含CPU和内存指标
4. 验证指标数据的时间序列正确
5. 检查指标值在合理范围内

**预期结果**:
- 成功收集CPU和内存指标
- 指标数据包含时间戳
- 值在合理范围内（CPU: 0-100%, 内存: 正数）

**通过标准**: 指标数据正确收集且格式正确

### TC-DC-004: 错误处理 - 文件不存在

**测试目的**: 验证对不存在的日志文件的错误处理

**前置条件**:
1. 确保文件`/tmp/nonexistent.log`不存在

**测试步骤**:
1. 尝试收集不存在的日志文件：
   ```bash
   claude witty-diagnosis:data-collector \
     --data-sources logs \
     --log-paths /tmp/nonexistent.log \
     --output-file /tmp/test-output-dc-004.json
   ```
2. 验证命令返回非零状态码
3. 检查错误信息明确指示文件不存在
4. 验证输出文件可能包含部分错误信息

**预期结果**:
- 命令执行失败
- 错误信息明确（如"FILE_NOT_FOUND"）
- 无有效数据输出

**通过标准**: 正确处理文件不存在错误

### TC-DC-005: 权限不足错误处理

**测试目的**: 验证对权限不足情况的错误处理

**前置条件**:
1. 创建无读取权限的测试文件：
   ```bash
   sudo touch /tmp/no-permission.log
   sudo chmod 000 /tmp/no-permission.log
   ```

**测试步骤**:
1. 尝试收集无权限的文件：
   ```bash
   claude witty-diagnosis:data-collector \
     --data-sources logs \
     --log-paths /tmp/no-permission.log \
     --output-file /tmp/test-output-dc-005.json
   ```
2. 验证命令返回非零状态码
3. 检查错误信息指示权限问题
4. 清理测试文件

**预期结果**:
- 命令执行失败
- 错误信息包含权限相关描述
- 无数据收集

**通过标准**: 正确处理权限错误

### TC-DC-006: 时间范围过滤

**测试目的**: 验证时间范围过滤功能

**前置条件**:
1. 准备包含时间戳的测试日志文件
2. 日志覆盖至少3小时的时间范围

**测试步骤**:
1. 收集最近1小时的日志：
   ```bash
   claude witty-diagnosis:data-collector \
     --data-sources logs \
     --log-paths /tmp/test-logs/timed.log \
     --time-window "1h" \
     --output-file /tmp/test-output-dc-006.json
   ```
2. 验证收集的日志时间戳在最近1小时内
3. 检查更早的日志被正确过滤

**预期结果**:
- 只收集时间范围内的日志
- 时间范围外的日志被正确排除
- 时间过滤功能正常工作

**通过标准**: 时间过滤准确无误

### TC-DC-007: 输出格式测试

**测试目的**: 验证不同的输出格式

**前置条件**:
1. 准备测试日志文件

**测试步骤**:
1. 测试JSON格式输出：
   ```bash
   claude witty-diagnosis:data-collector \
     --data-sources logs \
     --log-paths /tmp/test-logs/sample.log \
     --output-format json \
     --output-file /tmp/test-output-dc-007a.json
   ```
2. 测试CSV格式输出：
   ```bash
   claude witty-diagnosis:data-collector \
     --data-sources logs \
     --log-paths /tmp/test-logs/sample.log \
     --output-format csv \
     --output-file /tmp/test-output-dc-007b.csv
   ```
3. 验证两种格式的文件都能正确解析
4. 检查内容一致性

**预期结果**:
- 两种格式都成功输出
- 内容相同，只是格式不同
- 文件可被相应工具正确解析

**通过标准**: 所有输出格式正常工作

### TC-DC-008: 性能测试 - 大规模日志收集

**测试目的**: 验证处理大规模日志的性能

**前置条件**:
1. 准备包含10万条日志的大文件

**测试步骤**:
1. 执行大规模日志收集：
   ```bash
   time claude witty-diagnosis:data-collector \
     --data-sources logs \
     --log-paths /tmp/test-logs/large.log \
     --output-file /tmp/test-output-dc-008.json
   ```
2. 记录执行时间
3. 验证所有日志都被处理
4. 检查内存使用情况

**预期结果**:
- 成功处理所有日志
- 执行时间在可接受范围内（如<30秒）
- 内存使用稳定，无内存泄漏

**通过标准**: 性能指标满足要求

### TC-DC-009: 配置收集测试

**测试目的**: 验证系统配置收集功能

**前置条件**:
1. 系统有标准配置文件

**测试步骤**:
1. 收集系统配置：
   ```bash
   claude witty-diagnosis:data-collector \
     --data-sources config \
     --config-items system network services \
     --output-file /tmp/test-output-dc-009.json
   ```
2. 验证配置信息被正确收集
3. 检查敏感信息被适当处理

**预期结果**:
- 成功收集系统、网络、服务配置
- 配置信息格式正确
- 敏感信息（如密码）被过滤或加密

**通过标准**: 配置收集功能正常工作

### TC-DC-010: 集成测试 - 完整数据收集流程

**测试目的**: 验证完整的多类型数据收集流程

**前置条件**:
1. 测试环境准备就绪

**测试步骤**:
1. 执行完整数据收集：
   ```bash
   claude witty-diagnosis:data-collector \
     --data-sources logs metrics config \
     --log-paths /tmp/test-logs/system.log \
     --metric-types cpu memory \
     --config-items system \
     --time-window "30m" \
     --collection-frequency 10 \
     --output-file /tmp/test-output-dc-010.json
   ```
2. 验证所有数据类型都被收集
3. 检查输出文件结构正确
4. 验证数据完整性和一致性

**预期结果**:
- 成功收集日志、指标、配置数据
- 输出文件包含所有数据类型
- 数据质量符合要求

**通过标准**: 完整流程正常工作

## 测试数据清理

### 每次测试后清理
```bash
# 清理测试输出文件
rm -f /tmp/test-output-dc-*.json /tmp/test-output-dc-*.csv

# 恢复测试环境
# （根据具体测试环境决定）
```

### 全部测试完成后清理
```bash
# 清理所有测试数据
rm -rf /tmp/test-logs/
rm -f /tmp/test-output-*.json
rm -f /tmp/test-output-*.csv
```

## 测试执行计划

### 自动化测试脚本
```bash
#!/bin/bash
# 自动化测试脚本示例

echo "开始执行data-collector技能测试..."

# 准备测试环境
./setup-test-environment.sh

# 执行测试用例
for test_case in tc-dc-001 tc-dc-002 tc-dc-003 tc-dc-004 tc-dc-005 \
                 tc-dc-006 tc-dc-007 tc-dc-008 tc-dc-009 tc-dc-010; do
  echo "执行测试用例: $test_case"
  ./run-test.sh $test_case
  if [ $? -ne 0 ]; then
    echo "测试用例 $test_case 失败"
    exit 1
  fi
done

echo "所有测试用例执行完成"
```

### 手动测试步骤
1. 按照测试用例顺序执行
2. 记录每个测试用例的结果
3. 汇总测试报告

## 测试报告模板

### 测试执行摘要
- 测试开始时间: [日期时间]
- 测试结束时间: [日期时间]
- 测试用例总数: 10
- 通过用例数: [数字]
- 失败用例数: [数字]
- 通过率: [百分比]

### 详细测试结果
| 测试用例ID | 测试名称 | 状态 | 执行时间 | 备注 |
|------------|----------|------|----------|------|
| TC-DC-001 | 基本日志收集功能 | [通过/失败] | [时间] | [备注] |
| TC-DC-002 | 多源日志收集 | [通过/失败] | [时间] | [备注] |
| TC-DC-003 | 指标收集功能 | [通过/失败] | [时间] | [备注] |
| TC-DC-004 | 错误处理 - 文件不存在 | [通过/失败] | [时间] | [备注] |
| TC-DC-005 | 权限不足错误处理 | [通过/失败] | [时间] | [备注] |
| TC-DC-006 | 时间范围过滤 | [通过/失败] | [时间] | [备注] |
| TC-DC-007 | 输出格式测试 | [通过/失败] | [时间] | [备注] |
| TC-DC-008 | 性能测试 | [通过/失败] | [时间] | [备注] |
| TC-DC-009 | 配置收集测试 | [通过/失败] | [时间] | [备注] |
| TC-DC-010 | 集成测试 | [通过/失败] | [时间] | [备注] |

### 发现的问题
1. [问题描述]
   - 影响: [影响范围]
   - 优先级: [高/中/低]
   - 状态: [未解决/已解决/验证中]

### 测试结论
[总体测试结论，是否通过验收]

---

*测试文档版本：1.0.0*
*最后更新：2026-02-03*