# 命令定义规范

## 概述

本规范定义了witty-diagnosis-agent项目中命令的定义标准。统一的命令规范确保用户界面的一致性、命令的可发现性和使用体验的连贯性。

## 1. 命令设计原则

### 1.1 设计原则
- **一致性**：命令语法、选项命名、输出格式保持一致
- **可发现性**：命令和选项易于发现和理解
- **可组合性**：命令可以组合使用，支持管道和重定向
- **错误友好**：提供清晰的错误信息和恢复建议
- **渐进式**：从简单到复杂，支持逐步学习

### 1.2 命令分类
| 命令类别 | 用途 | 示例 | 特点 |
|----------|------|------|------|
| **诊断命令** | 执行系统诊断 | `diagnose`, `health-check` | 调用多个技能，生成报告 |
| **数据命令** | 数据收集和处理 | `collect-data`, `analyze-logs` | 专注于数据操作 |
| **管理命令** | 系统管理 | `config`, `skill`, `agent` | 管理命令和配置 |
| **工具命令** | 辅助工具 | `version`, `help`, `completion` | 提供工具功能 |

## 2. 命令文件结构

### 2.1 文件位置和命名
```
commands/
├── diagnose.md              # 主诊断命令
├── collect-data.md          # 数据收集命令
├── analyze-logs.md          # 日志分析命令
├── health-check.md          # 健康检查命令
├── config.md                # 配置管理命令
├── skill.md                 # 技能管理命令
├── agent.md                 # 代理管理命令
├── version.md               # 版本信息命令
└── help.md                  # 帮助命令
```

### 2.2 文件命名规范
- 使用kebab-case（短横线分隔的小写字母）
- 名称应简洁、描述性
- 避免使用通用词汇（如`run`, `exec`）
- 示例：`diagnose`, `collect-data`, `analyze-logs`

## 3. 命令文档结构

### 3.1 YAML Frontmatter（必需）

```yaml
---
description: 命令的简短描述（50-100字符）
disable-model-invocation: true|false  # 是否禁用模型调用
---
```

### 3.2 文档主体结构

```markdown
# [命令名称] 命令

## 概述
[命令的详细描述，包括功能、用途和适用场景]

## 命令语法
```bash
[命令语法示例]
```

## 选项说明
[详细的选项说明表格]

## 使用示例
[多个使用示例，从简单到复杂]

## 环境变量
[支持的环境变量说明]

## 配置文件
[配置文件格式和位置说明]

## 执行流程
[命令的详细执行流程]

## 输出格式
[不同输出格式的示例]

## 退出码
[退出码定义表格]

## 错误处理
[常见错误及解决方法]

## 性能考虑
[性能相关信息和优化建议]

## 安全考虑
[安全相关注意事项]

## 相关命令
[相关命令的引用]

## 更新日志
[命令的版本更新记录]
```

## 4. 命令语法规范

### 4.1 基本语法模式

```bash
# 模式1：简单命令
command

# 模式2：带选项的命令
command --option value

# 模式3：带位置参数的命令
command argument1 argument2

# 模式4：组合使用
command --option value argument | other-command
```

### 4.2 选项命名规范

#### 长选项（--option）
- 使用kebab-case：`--target-system`, `--log-level`
- 描述性名称：`--output-format`而非`--of`
- 避免缩写：`--configuration`而非`--config`（除非是标准缩写）

#### 短选项（-o）
- 单字母：`-v`, `-q`, `-h`
- 标准含义：
  - `-h`：帮助
  - `-v`：详细输出
  - `-q`：安静模式
  - `-V`：版本
  - `-f`：文件
  - `-o`：输出

#### 选项分组
```bash
# 布尔选项组
command --verbose --dry-run --force

# 值选项组
command --target system --format json --timeout 300

# 混合选项组
command --target system -v --output report.json
```

## 5. 选项定义规范

### 5.1 选项类型

| 类型 | 格式 | 示例 | 验证规则 |
|------|------|------|----------|
| **字符串** | `--option value` | `--target system` | 非空字符串 |
| **整数** | `--option 123` | `--timeout 300` | 正整数 |
| **浮点数** | `--option 12.34` | `--threshold 0.95` | 0.0-1.0 |
| **布尔值** | `--option` | `--verbose` | true/false |
| **枚举** | `--option value` | `--format json` | 预定义值列表 |
| **数组** | `--option val1,val2` | `--skills dc,la,fl` | 逗号分隔列表 |
| **文件路径** | `--option /path/file` | `--config config.yaml` | 有效文件路径 |

### 5.2 标准选项集

所有命令都应支持以下标准选项：

| 选项 | 短选项 | 类型 | 描述 | 默认值 |
|------|--------|------|------|--------|
| `--help` | `-h` | 布尔 | 显示帮助信息 | 无 |
| `--version` | `-V` | 布尔 | 显示版本信息 | 无 |
| `--verbose` | `-v` | 布尔 | 启用详细输出 | `false` |
| `--quiet` | `-q` | 布尔 | 启用安静模式 | `false` |
| `--config` | `-c` | 文件路径 | 指定配置文件 | 无 |
| `--log-level` | 无 | 枚举 | 设置日志级别 | `"info"` |
| `--dry-run` | 无 | 布尔 | 模拟执行 | `false` |
| `--force` | `-f` | 布尔 | 强制执行 | `false` |

### 5.3 诊断命令标准选项

诊断相关命令还应支持：

| 选项 | 短选项 | 类型 | 描述 | 默认值 |
|------|--------|------|------|--------|
| `--target` | `-t` | 枚举 | 诊断目标 | `"system"` |
| `--skills` | `-s` | 数组 | 技能列表 | 所有启用技能 |
| `--format` | 无 | 枚举 | 输出格式 | `"text"` |
| `--output` | `-o` | 文件路径 | 输出文件 | 无 |
| `--timeout` | `-T` | 整数 | 超时时间（秒） | `300` |

## 6. 参数验证规范

### 6.1 验证规则定义

```yaml
validation:
  required_options:
    - "target"
    - "session-id"

  option_constraints:
    timeout:
      type: "integer"
      min: 1
      max: 3600
      default: 300

    target:
      type: "enum"
      allowed_values:
        - "system"
        - "network"
        - "storage"
        - "security"
      default: "system"

    format:
      type: "enum"
      allowed_values:
        - "text"
        - "json"
        - "yaml"
        - "html"
      default: "text"
```

### 6.2 验证错误消息

```json
{
  "error": "VALIDATION_FAILED",
  "message": "参数验证失败",
  "details": [
    {
      "option": "timeout",
      "error": "值必须大于0",
      "provided": -1,
      "allowed": "正整数"
    },
    {
      "option": "target",
      "error": "无效的值",
      "provided": "invalid",
      "allowed": ["system", "network", "storage", "security"]
    }
  ],
  "suggestions": [
    "使用 --help 查看选项说明",
    "检查参数值是否符合要求"
  ]
}
```

## 7. 输出格式规范

### 7.1 输出格式支持

所有命令应支持以下输出格式：

#### 文本格式（默认）
```
命令执行报告
=============

会话ID: session-001
状态: 成功
执行时间: 45.2秒

摘要
----
系统健康状态: 良好
发现问题: 2个
建议: 3条

详细结果
--------
1. [WARNING] 内存使用率较高
   当前: 85%，阈值: 80%
   建议: 监控内存使用趋势

2. [INFO] 磁盘空间充足
   使用率: 45%
   状态: 正常
```

#### JSON格式
```json
{
  "command": "diagnose",
  "session_id": "session-001",
  "status": "success",
  "execution_time": 45.2,
  "summary": {
    "health_status": "good",
    "issues_found": 2,
    "recommendations": 3
  },
  "results": [
    {
      "severity": "warning",
      "component": "memory",
      "description": "内存使用率较高",
      "current_value": 85,
      "threshold": 80,
      "recommendation": "监控内存使用趋势"
    }
  ]
}
```

#### YAML格式
```yaml
command: diagnose
session_id: session-001
status: success
execution_time: 45.2
summary:
  health_status: good
  issues_found: 2
  recommendations: 3
results:
  - severity: warning
    component: memory
    description: 内存使用率较高
    current_value: 85
    threshold: 80
    recommendation: 监控内存使用趋势
```

### 7.2 输出控制选项

```bash
# 控制输出格式
command --format json
command --format yaml
command --format text

# 控制输出目标
command --output report.json
command --output /dev/stdout
command --output /dev/null

# 控制输出详细程度
command --verbose      # 详细输出
command --quiet        # 最小输出
command --silent       # 无输出（仅退出码）
```

## 8. 错误处理规范

### 8.1 错误分类

| 错误类别 | 退出码 | 描述 | 处理策略 |
|----------|--------|------|----------|
| **用户错误** | 1-10 | 用户输入错误 | 显示帮助信息，建议正确用法 |
| **配置错误** | 11-20 | 配置问题 | 显示配置错误，建议修复 |
| **依赖错误** | 21-30 | 依赖缺失 | 显示缺失依赖，提供安装指导 |
| **权限错误** | 31-40 | 权限不足 | 显示权限要求，建议提升权限 |
| **资源错误** | 41-50 | 资源不足 | 显示资源状态，建议释放资源 |
| **系统错误** | 51-60 | 系统问题 | 显示系统错误，建议检查系统 |
| **网络错误** | 61-70 | 网络问题 | 显示网络状态，建议检查连接 |
| **超时错误** | 71-80 | 执行超时 | 显示超时信息，建议增加超时时间 |

### 8.2 错误消息格式

```json
{
  "error": {
    "code": "INVALID_PARAMETER",
    "message": "参数 'timeout' 的值无效",
    "details": {
      "parameter": "timeout",
      "provided": -1,
      "expected": "正整数",
      "suggestion": "使用 --timeout 300 设置超时时间"
    }
  },
  "command": "diagnose",
  "timestamp": "2026-02-03T17:30:00Z"
}
```

## 9. 命令组合规范

### 9.1 管道支持

```bash
# 基本管道
command1 | command2

# 带选项的管道
command1 --option value | command2 --filter pattern

# 多级管道
command1 | command2 | command3 > output.txt
```

### 9.2 命令链支持

```bash
# 顺序执行
command1 && command2 && command3

# 条件执行
command1 || command2

# 后台执行
command1 & command2
```

### 9.3 输入输出重定向

```bash
# 输入重定向
command < input.txt

# 输出重定向
command > output.txt
command >> output.txt  # 追加

# 错误重定向
command 2> error.log
command 2>&1           # 合并输出和错误

# 所有重定向
command < input.txt > output.txt 2> error.log
```

## 10. 命令发现和帮助

### 10.1 帮助系统

```bash
# 显示所有命令
witty-diagnosis --help

# 显示命令帮助
witty-diagnosis diagnose --help

# 显示命令用法示例
witty-diagnosis diagnose --help-examples

# 显示命令选项详情
witty-diagnosis diagnose --help-options
```

### 10.2 命令补全

```bash
# Bash补全
source <(witty-diagnosis completion bash)

# Zsh补全
source <(witty-diagnosis completion zsh)

# Fish补全
witty-diagnosis completion fish | source
```

### 10.3 命令搜索

```bash
# 搜索命令
witty-diagnosis search "diagnose"

# 列出所有命令
witty-diagnosis list-commands

# 列出命令类别
witty-diagnosis list-categories
```

## 11. 性能优化规范

### 11.1 命令执行优化

```yaml
performance:
  # 缓存配置
  cache:
    enabled: true
    ttl_seconds: 300
    strategy: "per_session"

  # 并行执行
  parallelism:
    enabled: true
    max_workers: 4

  # 资源限制
  resources:
    memory_limit_mb: 512
    cpu_limit_percent: 50

  # 懒加载
  lazy_loading:
    enabled: true
    load_on_demand: true
```

### 11.2 输出优化

```bash
# 最小化输出
command --quiet --format json | jq '.summary'

# 增量输出
command --stream --format json

# 压缩输出
command --format json --compress | gzip > output.json.gz
```

## 12. 安全规范

### 12.1 权限控制

```yaml
security:
  # 命令权限级别
  permission_levels:
    diagnose: "operator"
    collect-data: "operator"
    config: "admin"
    skill: "admin"

  # 敏感操作确认
  confirmation:
    required_for:
      - "force"
      - "no-backup"
      - "dangerous"

  # 审计日志
  audit:
    enabled: true
    log_all_commands: true
    sensitive_fields: ["password", "api_key", "secret"]
```

### 12.2 输入验证

```bash
# 安全模式
command --safe-mode

# 输入验证
command --validate-input

# 沙箱执行
command --sandbox
```

## 13. 测试规范

### 13.1 命令测试

```yaml
testing:
  # 单元测试
  unit_tests:
    enabled: true
    coverage_threshold: 80

  # 集成测试
  integration_tests:
    enabled: true
    test_scenarios:
      - "basic_usage"
      - "error_handling"
      - "performance"

  # 端到端测试
  e2e_tests:
    enabled: true
    environments:
      - "development"
      - "staging"
```

### 13.2 测试用例示例

```bash
# 测试基本功能
test_command_basic() {
  output=$(witty-diagnosis diagnose --dry-run)
  assert_contains "$output" "诊断报告"
}

# 测试错误处理
test_command_error() {
  output=$(witty-diagnosis diagnose --invalid-option 2>&1)
  assert_contains "$output" "无效选项"
}

# 测试性能
test_command_performance() {
  start_time=$(date +%s%N)
  witty-diagnosis diagnose --quiet
  end_time=$(date +%s%N)
  duration=$(( (end_time - start_time) / 1000000 ))
  assert_less_than "$duration" 5000  # 5秒内完成
}
```

## 14. 版本兼容性

### 14.1 向后兼容性

```yaml
compatibility:
  # 选项兼容性
  options:
    deprecated:
      - name: "old-option"
        since: "2.0.0"
        alternative: "new-option"
        removal: "3.0.0"

    renamed:
      - old: "output-format"
        new: "format"
        since: "1.5.0"

  # 输出格式兼容性
  output_formats:
    supported:
      - "v1"
      - "v2"
    default: "v2"
    fallback: "v1"
```

### 14.2 迁移指南

```markdown
## 从 v1.x 迁移到 v2.x

### 变更的选项
- `--output-format` 重命名为 `--format`
- `--skills-list` 重命名为 `--skills`

### 废弃的功能
- `--legacy-mode` 已废弃，使用 `--compatibility-mode`

### 迁移步骤
1. 更新命令调用
2. 更新配置文件
3. 测试迁移后的功能
```

---

*文档版本：1.0.0*
*创建日期：2026-02-03*
*更新日期：2026-02-03*
