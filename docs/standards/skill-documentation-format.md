# 技能文档格式规范

## 概述

本规范定义了witty-diagnosis-agent项目中技能文档的标准格式和结构。所有技能文档必须遵循此规范以确保一致性和可维护性。

## 1. 技能目录结构

每个技能必须位于独立的目录中，目录结构如下：

```
skills/
├── skill-name/                    # 技能目录（使用kebab-case命名）
│   ├── SKILL.md                   # 主技能文档（必需）
│   ├── examples/                  # 示例目录（可选）
│   │   ├── basic-usage.md         # 基础使用示例
│   │   └── advanced-scenarios.md  # 高级场景示例
│   ├── tests/                     # 测试目录（可选）
│   │   ├── test-basic.md          # 基础测试用例
│   │   └── test-edge-cases.md     # 边界条件测试
│   └── assets/                    # 资源文件目录（可选）
│       ├── diagrams/              # 图表
│       └── templates/             # 模板文件
```

## 2. 技能命名规范

### 2.1 目录命名

- 使用kebab-case（短横线分隔的小写字母）
- 名称应简洁、描述性
- 避免使用通用词汇（如"utils"、"helpers"）
- 示例：`data-collector`, `root-cause-analysis`, `log-analyzer`

### 2.2 技能标识符

- 格式：`witty-diagnosis:skill-name`
- 用于在命令和配置中引用技能
- 示例：`witty-diagnosis:data-collector`

## 3. SKILL.md 文档结构

### 3.1 YAML Frontmatter（必需）

```yaml
---
name: skill-name                    # 技能名称（kebab-case）
description: 简短描述技能的功能     # 50-100字符的简短描述
version: 1.0.0                      # 技能版本（语义化版本）
category: core|analysis|support     # 技能分类
requires:                           # 依赖的其他技能（可选）
  - witty-diagnosis:data-collector
  - witty-diagnosis:log-analyzer
author: 作者姓名                     # 技能作者
created: 2026-02-03                 # 创建日期
updated: 2026-02-03                 # 最后更新日期
tags:                               # 标签（可选）
  - data-collection
  - system-monitoring
  - euler-os
---
```

### 3.2 文档主体结构

```markdown
# 技能名称（人类可读名称）

## 概述

简要介绍技能的目的、功能和适用场景。说明技能在整个诊断流程中的位置和作用。

## 使用时机

明确说明何时应该使用此技能，包括：
- 典型的触发条件
- 预期的输入状态
- 与其他技能的配合关系

## 输入要求

### 必需输入
- 描述技能执行必需的数据和参数
- 格式要求、数据类型、取值范围

### 可选输入
- 描述可选的配置参数
- 默认值和行为

### 输入格式示例

{
  "session_id": "string",
  "target": "system|network|storage|security",
  "parameters": {
    "timeout": 300,
    "verbosity": "info"
  }
}

## 执行步骤

详细描述技能的执行流程，包括：

1. 初始化阶段
2. 数据收集/处理阶段
3. 分析/计算阶段
4. 结果生成阶段

每个步骤应包含：

- 具体操作
- 使用的工具或方法
- 错误处理和恢复机制

## 输出格式

### 成功输出

{
  "status": "success",
  "session_id": "string",
  "execution_time": 123.45,
  "results": {
    // 技能特定的结果数据
  },
  "metadata": {
    "skill_version": "1.0.0",
    "timestamp": "2026-02-03T17:30:00Z"
  }
}

### 错误输出

{
  "status": "error",
  "session_id": "string",
  "error_code": "ERROR_CODE",
  "error_message": "人类可读的错误描述",
  "details": {
    // 详细的错误信息
  },
  "suggestions": [
    "可能的修复建议"
  ]
}

## 示例

### 示例1：基础使用

# 命令示例
claude witty-diagnosis:skill-name --parameter value

# 输入数据示例
{
  "target": "system",
  "timeout": 300
}

# 输出结果示例
{
  "status": "success",
  "results": {
    "issues_found": 2,
    "severity": "warning"
  }
}

### 示例2：高级场景

描述更复杂的用例和配置。

## 注意事项

### 安全注意事项

- 权限要求
- 数据敏感性
- 操作风险

### 性能注意事项

- 资源消耗
- 执行时间
- 并发限制

### 环境要求

- 系统依赖
- 软件版本
- 配置要求
```

## 4. 测试用例

### 测试1：正常流程测试

- **输入**：标准的有效输入
- **预期输出**：成功状态和正确结果
- **验证点**：结果准确性、执行时间

### 测试2：边界条件测试

- **输入**：边界值或极端条件
- **预期输出**：适当的错误处理或特殊结果
- **验证点**：健壮性、错误处理

### 测试3：错误处理测试

- **输入**：无效或损坏的输入
- **预期输出**：清晰的错误信息和恢复建议
- **验证点**：错误消息质量、恢复能力

## 4. 质量要求

### 4.1 文档完整性

- 所有必需部分必须完整
- 示例必须可运行
- 接口定义必须准确

### 4.2 可读性

- 使用清晰的语言
- 结构层次分明
- 代码示例格式正确

### 4.3 一致性

- 术语使用一致
- 格式规范统一
- 与其他技能文档风格一致

### 4.4 可维护性

- 版本控制清晰
- 更新日志完整
- 依赖关系明确

## 5. 版本管理

### 5.1 版本号规则

使用语义化版本控制：

- **主版本号**：不兼容的API修改
- **次版本号**：向下兼容的功能性新增
- **修订号**：向下兼容的问题修正

### 5.2 更新要求

- 重大变更需要更新主版本号
- 所有变更必须更新文档
- 向后兼容性必须测试
