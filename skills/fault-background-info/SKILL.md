---
name: fault-background-info
description: 提供不同故障场景的背景信息和日志获取策略。
---

## 故障背景信息 (Fault Background Info)

本 Skill 用于获取特定故障场景的背景知识。

### 工作流程 (Workflow)

**必须**遵循以下步骤进行故障分析：

1.  **场景识别 (Identify Scenario)**
    *   **浏览目录**: 检查 该skill的`references` 目录下有哪些可用文档。
    *   **匹配场景**: 根据用户描述的故障特征，在上述目录下寻找最匹配的场景文件。
    *   *原则*: **严禁发散**，只能选择 `references/` 目录下存在的场景。

2.  **获取背景 (Get Context)**
    *   加载并阅读匹配到的 Reference 文档。
    *   了解该场景的架构、核心指标和故障模式。

3.  **数据准备 (Data Preparation)**
    *   **查阅文档**: 检查 Reference 文档中的“日志策略”章节。
    *   **执行操作**:
        *   如果文档说明**无需下载**，则直接进行分析。
        *   如果文档要求**下载日志**，请根据文档内的参数说明，使用 `scripts/log_fetcher.py` 工具。

### 工具：日志下载 (Log Fetcher)

**脚本路径**: `.claude/skills/fault-background-info/scripts/log_fetcher.py`

**使用说明**:

*   具体的下载命令（`--mode`, `--servers` 等）**必须**以 Reference 文档中的说明为准。
*   **Windows 兼容性**: 如遇 `bcrypt` 报错，请降级至 3.2.2 (`pip install bcrypt==3.2.2`)。


