# witty-diagnosis-agent

witty-diagnosis-agent 是一个自动化诊断系统，旨在为复杂的系统问题提供标准化的分析和故障排除。当前版本兼容支持 **OpenCode** 运行环境。

## 核心设计理念 (Core Philosophy)

本方案严格遵循 **"发现→收集→定位→根因→方案→实施→验证"** 的标准化运维作业流程，结合**多模块协作 (Multi-Module)** 架构，实现全生命周期的自动化管理。

### 核心流程图解

`1.问题输入/采集` → `2.收集信息` → `3.定位故障` → `4.分析根因` → `5.制定方案` → `6.实施修复` → `7.验证效果`

## 核心组件功能 (Core Components & Functions)

| 组件名称 | 功能描述 (Function) |
| :--- | :--- |
| **Commander** | **1. 发现问题 & 全局统筹**。作为系统入口接收告警或用户输入，初始化故障上下文，**路由请求**，**调度**各功能模块。 |
| **Investigator** | **2. 收集信息 & 3. 定位故障**。**并发执行**多个采集任务收集数据，并按“应用→系统→网络→硬件”逻辑进行分层定位。 |
| **Analyst** | **4. 分析根因**。基于收集的信息进行**逻辑分析**，确定 Root Cause。 |
| **Strategist** | **5. 制定方案**。生成修复计划，包含临时止血措施和永久修复方案，并评估风险。 |
| **Guardian** | **风险控制**。在 Step 5/6 阶段审查修复方案的风险，执行审批策略，防止二次故障。 |
| **Operator** | **6. 实施修复**。执行 Strategist 制定的修复脚本（需通过 Guardian 审批）。 |
| **Auditor** | **7. 验证效果**。执行冒烟测试 (Smoke Test) 和指标回归检查。 |

## 功能扩展机制 (Functional Extensibility)

系统支持高度的扩展性，允许在标准流程中灵活插入或替换**功能插件**。

### 1. 阶段扩展 (Phase Extensions)
支持在任意标准阶段（如 `Investigator` 之后，`Analyst` 之前）挂载**自定义插件 (Hook Plugins)**。
*   **用途**: 针对特定技术栈（如 Redis, Kafka）增加专用的信息收集或分析步骤。
*   **机制**: **执行引擎**会自动检测并执行注册的 `pre-step` 或 `post-step` **扩展插件**。

### 2. 端到端接管 (End-to-End Override)
支持跳过标准的 7 步流程，直接调用专用的**端到端流程 (Dedicated Workflows)**。
*   **用途**: 针对已知的高频特定故障模式（如 "K8s Pod OOM" 或 "MySQL 死锁"），直接执行固化的诊断与修复剧本。
*   **机制**: `Commander` 在第一步识别场景后，可直接路由至**专用流程**，绕过通用的分层排查流程。




## 安装与使用 (Installation & Usage)

### 前置要求 (Prerequisites)

本系统依赖 **OpenCode** 运行时环境。请参考 [OpenCode 官方文档](https://github.com/anomalyco/opencode) 完成安装。

### 安装 (Installation)

推荐使用 `bunx` 或 `npx` 进行快速安装：

```bash
bunx witty-diagnosis-agent install # recommended
# or
npx witty-diagnosis-agent install
```

### 快速开始 (Quick Start)

通过 CLI 交互，体验基于核心组件协作的全流程诊断：

1.  **启动诊断 (Commander)**
    初始化故障上下文，自动触发信息收集：
    ```bash
    witty-diagnosis start --incident-id <ID> --desc "API响应慢"
    ```
    *系统将调度 `Investigator` 并行采集数据，并由 `Analyst` 产出根因分析报告。*

2.  **审批修复方案 (Guardian)**
    当 `Strategist` 生成修复方案后，系统会暂停并等待确认：
    ```bash
    witty-diagnosis approve --plan-id <PLAN_ID>
    ```
    *`Guardian` 组件将拦截所有高危操作，确保人工确认后才由 `Operator` 执行修复。*

3.  **验证结果 (Auditor)**
    修复完成后，自动运行回归测试：
    ```bash
    witty-diagnosis verify --incident-id <ID>
    ```
    *由 `Auditor` 确认核心指标恢复基线。*



## 功能扩展 (Extending Functionality)
参考前文“功能扩展机制”，编写自定义插件配置。




