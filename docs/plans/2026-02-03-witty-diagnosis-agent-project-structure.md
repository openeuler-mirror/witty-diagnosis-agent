# 欧拉OS智能诊断技能项目结构规划

> **For Claude:** 项目结构规划文档，用于指导智能诊断技能集合的开发。

**Goal:** 设计符合Claude插件风格规范的智能诊断技能项目结构，包含10个技能模块、标准化目录结构和文档规范。

**Architecture:** 基于superpowers技能结构，采用模块化设计，每个技能独立目录，支持技能组合调用。项目分为核心诊断层、分析支撑层、管理支持层三层架构。

**Tech Stack:** 基于superpowers技能规范的模块化设计，支持技能组合调用和扩展

---

## 项目概述

本项目将创建10个智能诊断技能，按照欧拉OS智能诊断技能设计文档的要求：

1. **核心诊断层** (5个技能)
   - data-collector: 多源数据采集
   - fault-localization: 故障定位
   - root-cause-analysis: 根因分析
   - controlled-repair: 可控修复
   - intelligent-inspection: 智能巡检

2. **分析支撑层** (3个技能)
   - log-analyzer: 日志分析
   - metric-analyzer: 指标分析
   - trace-analyzer: 链路追踪分析

3. **管理支持层** (2个技能)
   - knowledge-base: 知识库管理
   - config-manager: 配置管理

## 目录结构设计 (基于superpowers项目优化)

参考superpowers项目的结构，优化后的目录结构如下：

```
witty-diagnosis-agent/
├── README.md                          # 项目主文档
├── LICENSE                            # 项目许可证
├── .gitignore                         # Git忽略文件
├── .gitattributes                     # Git属性配置
├── .claude-plugin/                    # Claude插件配置目录
│   ├── plugin.json                    # 插件配置文件
│   └── marketplace.json               # 市场配置文件
├── commands/                          # 命令定义目录
│   ├── diagnose.md                    # 诊断命令
│   ├── collect-data.md                # 数据收集命令
│   ├── analyze-logs.md                # 日志分析命令
│   └── repair-system.md               # 系统修复命令
├── docs/                              # 文档目录
│   ├── plans/                         # 实现计划
│   ├── architecture/                  # 架构设计
│   ├── api/                           # API文档
│   ├── skills/                        # 技能文档
│   └── deployment/                    # 部署指南
├── skills/                            # 技能目录 (superpowers风格)
│   ├── data-collector/                # 技能1: 数据采集
│   │   ├── SKILL.md                   # 技能主文档 (YAML frontmatter + Markdown)
│   │   ├── CREATION-LOG.md            # 创建日志
│   │   ├── examples/                  # 示例目录
│   │   │   ├── collect-system-logs.md # 系统日志收集示例
│   │   │   └── collect-metrics.md     # 指标收集示例
│   │   └── tests/                     # 测试目录
│   │       └── test-data-collection.md # 数据收集测试
│   ├── fault-localization/            # 技能2: 故障定位
│   ├── root-cause-analysis/           # 技能3: 根因分析
│   ├── controlled-repair/             # 技能4: 可控修复
│   ├── intelligent-inspection/        # 技能5: 智能巡检
│   ├── log-analyzer/                  # 技能6: 日志分析
│   ├── metric-analyzer/               # 技能7: 指标分析
│   ├── trace-analyzer/                # 技能8: 链路追踪分析
│   ├── knowledge-base/                # 技能9: 知识库管理
│   └── config-manager/                # 技能10: 配置管理
├── lib/                               # 共享库目录
│   ├── core/                          # 核心库
│   │   ├── skill-base.js              # 技能基类
│   │   ├── utils.js                   # 工具函数
│   │   └── interfaces.js              # 接口定义
│   ├── euler-os/                      # 欧拉OS特定库
│   └── diagnosis/                     # 诊断相关库
├── tests/                             # 项目级测试目录
│   ├── integration/                   # 集成测试
│   ├── unit/                          # 单元测试
│   └── e2e/                           # 端到端测试
├── hooks/                             # 钩子脚本目录
│   ├── hooks.json                     # 钩子配置
│   └── session-start.sh               # 会话启动脚本
├── agents/                            # 代理定义目录
│   ├── diagnosis-agent.md             # 诊断代理定义
│   └── repair-agent.md                # 修复代理定义
└── config/                            # 项目配置目录
    ├── global.yaml                    # 全局配置
    ├── skills/                        # 技能配置
    └── euler-os/                      # 欧拉OS特定配置
```

## 技能接口规范 (基于superpowers项目)

参考superpowers项目的技能格式，每个技能必须遵循以下规范：

### 1. SKILL.md 文件格式

每个技能的SKILL.md文件必须包含：

**YAML Frontmatter:**
```yaml
---
name: "data-collector"
description: "Collect multi-source system data including logs, metrics, processes, and network status"
version: "0.1.0"
author: "Witty Diagnosis Team"
category: "core-diagnosis"
prerequisites: []
related_skills: ["log-analyzer", "metric-analyzer"]
---
```

**文档结构:**
1. **概述**: 技能的目的和适用场景
2. **使用时机**: 何时应该使用此技能
3. **输入要求**: 技能需要的输入数据格式
4. **执行步骤**: 详细的执行流程（分步骤）
5. **输出格式**: 技能生成的输出数据格式
6. **示例**: 具体的使用示例
7. **注意事项**: 使用时的注意事项和限制
8. **测试用例**: 技能的验证方法

### 2. 技能执行流程

每个技能定义清晰的执行流程：

1. **输入验证**: 验证输入数据的完整性和格式
2. **数据收集**: 收集必要的系统数据
3. **分析处理**: 对数据进行分析处理
4. **结果生成**: 生成诊断结果或修复建议
5. **输出格式化**: 将结果格式化为标准输出格式

### 3. 数据格式规范

**输入格式** (JSON):
```json
{
  "system": "euler-os",
  "components": ["logs", "metrics", "processes"],
  "time_range": "last_1_hour",
  "config": {
    "log_path": "/var/log/euler",
    "metric_interval": "5m"
  }
}
```

**输出格式** (JSON):
```json
{
  "success": true,
  "diagnosis": {
    "issue_found": true,
    "issue_type": "performance_degradation",
    "affected_components": ["service-a", "service-b"],
    "confidence": 0.85,
    "recommendations": [
      {
        "action": "restart_service",
        "service": "service-a",
        "priority": "high",
        "requires_approval": true
      }
    ]
  },
  "collected_data": {
    "logs": [...],
    "metrics": {...},
    "processes": [...]
  },
  "metadata": {
    "skill": "data-collector",
    "execution_time": "2026-02-03T10:30:00Z",
    "duration_ms": 1250
  }
}
```

### 4. 技能间协作

技能支持管道式组合调用：
- 一个技能的输出可以作为另一个技能的输入
- 支持技能链式调用（如：data-collector → log-analyzer → fault-localization）
- 每个技能保持独立，通过标准接口通信

## 实施原则 (基于superpowers项目)

1. **文档化优先**: 技能以文档形式定义，包含清晰的执行步骤和示例
2. **标准化格式**: 所有技能使用统一的SKILL.md格式（YAML frontmatter + Markdown）
3. **模块化设计**: 每个技能独立目录，包含完整文档、示例和测试
4. **可组合性**: 技能支持管道式组合调用，输出格式标准化
5. **平台适配**: 支持Claude Code、Codex、OpenCode等多个AI开发平台
6. **测试驱动**: 每个技能包含测试用例和验证方法
7. **安全可控**: 修复操作需要明确标记和人工确认
8. **可扩展性**: 易于添加新的诊断技能，遵循相同的结构和规范

---

## 项目开发阶段规划 (基于superpowers项目)

### 第一阶段：基础框架搭建 (Week 1-2)

**目标**: 建立项目基础结构，定义核心规范和模板

**主要任务**:
1. **项目骨架创建**
   - 创建标准目录结构（参考优化后的目录结构设计）
   - 配置.gitignore、.gitattributes和基础配置文件
   - 创建.claude-plugin目录和配置文件（plugin.json, marketplace.json）
   - 编写项目README.md和LICENSE文件

2. **核心规范定义**
   - 定义技能文档格式规范（YAML frontmatter + Markdown结构）
   - 创建技能开发模板和示例
   - 建立数据格式规范（输入/输出JSON格式）
   - 创建命令定义模板（commands/目录）

3. **开发环境配置**
   - 设置技能文档生成工具和模板
   - 配置测试验证流程
   - 建立文档质量检查标准
   - 创建hooks/目录和会话启动脚本

### 第二阶段：核心诊断技能开发 (Week 3-6)

**目标**: 创建5个核心诊断技能的完整文档和测试

**技能开发顺序**:
1. **data-collector** (数据采集技能)
   - SKILL.md: 多源数据采集流程文档
   - 包含：系统日志收集、性能指标监控、进程信息获取、网络状态检查
   - 示例：collect-system-logs.md, collect-metrics.md
   - 测试：test-data-collection.md

2. **fault-localization** (故障定位技能)
   - SKILL.md: 故障影响范围分析流程
   - 包含：服务依赖关系分析、故障传播路径识别、影响组件确定
   - 示例：locate-service-failure.md, identify-impact-scope.md
   - 测试：test-fault-localization.md

3. **root-cause-analysis** (根因分析技能)
   - SKILL.md: 根因推理和分析流程
   - 包含：历史故障模式匹配、因果关系分析、根因确定逻辑
   - 示例：analyze-performance-issue.md, find-root-cause.md
   - 测试：test-root-cause-analysis.md

4. **controlled-repair** (可控修复技能)
   - SKILL.md: 安全修复操作流程
   - 包含：修复操作安全控制、操作回滚机制、修复效果验证
   - 示例：restart-service-safely.md, rollback-configuration.md
   - 测试：test-controlled-repair.md

5. **intelligent-inspection** (智能巡检技能)
   - SKILL.md: 系统巡检流程
   - 包含：巡检策略定义、异常模式识别、巡检报告生成
   - 示例：daily-system-check.md, performance-inspection.md
   - 测试：test-intelligent-inspection.md

**每个技能开发包含**:
- SKILL.md主文档（YAML frontmatter + 完整执行步骤）
- CREATION-LOG.md创建日志
- examples/目录下的使用示例
- tests/目录下的测试用例
- 相关配置模板和工具脚本

### 第三阶段：分析支撑技能开发 (Week 7-8)

**目标**: 创建3个分析支撑技能的完整文档

**技能开发**:
1. **log-analyzer** (日志分析技能)
   - SKILL.md: 日志解析和分析流程
   - 包含：日志解析引擎、异常日志识别、日志模式分析
   - 示例：analyze-error-logs.md, detect-anomaly-patterns.md

2. **metric-analyzer** (指标分析技能)
   - SKILL.md: 性能指标监控和分析流程
   - 包含：指标收集、阈值检测、趋势分析、预警生成
   - 示例：monitor-cpu-usage.md, analyze-metric-trends.md

3. **trace-analyzer** (链路追踪分析技能)
   - SKILL.md: 服务调用链路分析流程
   - 包含：调用链路重建、性能瓶颈分析、依赖关系可视化
   - 示例：trace-service-calls.md, identify-bottlenecks.md

### 第四阶段：管理支持技能开发 (Week 9)

**目标**: 创建2个管理支持技能的完整文档

**技能开发**:
1. **knowledge-base** (知识库管理技能)
   - SKILL.md: 故障知识管理流程
   - 包含：知识存储格式、检索接口、更新机制、知识验证
   - 示例：add-failure-pattern.md, search-solutions.md

2. **config-manager** (配置管理技能)
   - SKILL.md: 系统配置管理流程
   - 包含：配置版本控制、配置分发、配置验证、回滚机制
   - 示例：update-service-config.md, validate-configuration.md

### 第五阶段：命令和代理集成 (Week 10)

**目标**: 创建命令定义和代理集成

**主要任务**:
1. **命令定义创建**
   - commands/diagnose.md: 完整诊断流程命令
   - commands/collect-data.md: 数据收集命令
   - commands/analyze-logs.md: 日志分析命令
   - commands/repair-system.md: 系统修复命令

2. **代理定义创建**
   - agents/diagnosis-agent.md: 诊断代理定义
   - agents/repair-agent.md: 修复代理定义

3. **技能集成测试**
   - 创建技能组合测试用例
   - 验证技能间数据流传递
   - 测试命令执行流程

4. **文档完善**
   - 创建用户使用手册
   - 编写部署配置指南
   - 生成API文档（如需要）

### 第六阶段：平台适配和优化 (Week 11-12)

**目标**: 平台适配和项目优化

**主要任务**:
1. **平台适配**
   - 验证Claude Code平台兼容性
   - 测试Codex平台集成（如需要）
   - 验证OpenCode平台支持（如需要）

2. **项目优化**
   - 优化技能文档结构和内容
   - 改进示例的实用性和可读性
   - 增强测试用例的覆盖范围

3. **质量保证**
   - 执行全面的文档审查
   - 验证所有技能的功能完整性
   - 测试命令和代理的可用性

4. **发布准备**
   - 更新版本号和发布说明
   - 准备市场配置文件
   - 创建安装和配置指南

---

## 成功标准 (基于文档化技能)

1. **文档完整性**: 10个技能全部有完整的SKILL.md文档，包含YAML frontmatter、详细执行步骤、示例和测试
2. **格式标准化**: 所有技能遵循统一的文档格式和结构规范
3. **功能完整性**: 技能覆盖完整的诊断流程，从数据采集到修复验证
4. **可测试性**: 每个技能包含可执行的测试用例和验证方法
5. **平台兼容性**: 支持Claude Code平台，可通过.claude-plugin配置使用
6. **可组合性**: 技能支持管道式组合调用，数据格式标准化
7. **易用性**: 命令定义清晰，用户可以通过简单命令调用诊断功能

## 风险与缓解 (基于文档化技能)

1. **文档质量风险**: 技能文档不清晰或执行步骤不完整
   - **缓解**: 建立文档审查流程，使用模板确保一致性，包含详细示例

2. **技能依赖风险**: 技能间依赖关系复杂，组合调用困难
   - **缓解**: 明确定义输入输出格式，使用标准化数据接口，提供组合示例

3. **执行一致性风险**: 不同用户执行相同技能可能得到不同结果
   - **缓解**: 提供详细的执行步骤和决策逻辑，包含常见场景处理

4. **安全风险**: 修复操作可能导致系统不稳定
   - **缓解**: 在SKILL.md中明确标记需要人工确认的操作，提供回滚步骤

5. **扩展性风险**: 新增技能困难，与现有结构不一致
   - **缓解**: 提供完整的技能开发模板和示例，建立技能开发指南

6. **平台适配风险**: 在不同AI开发平台上兼容性问题
   - **缓解**: 遵循superpowers项目的最佳实践，测试多平台兼容性

7. **维护风险**: 随着技能数量增加，文档维护困难
   - **缓解**: 建立技能目录索引，定期审查和更新，保持文档一致性