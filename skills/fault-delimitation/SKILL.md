---
name: fault-delimitation
description: 故障定界 Skill。使用指标分析工具识别可疑故障组件和关键异常指标。
---

## 故障定界 (Fault Delimitation)

本 Skill 负责在给定的故障时间范围和场景下，从指标侧识别最有可能存在问题的组件及其关键异常指标。

## 目标与职责

- 核心目标：仅使用已提供的指标分析工具，完成从数据加载到异常组件识别的端到端流程。
- **时间对齐（Time Alignment）要求**：接收上游传入的时间窗口后，在执行分析工具前，务必确认查询的时间范围与用户描述的故障发生时间一致。
  - **检查数据有效性**：在正式分析前，先检查指标数据的时间覆盖范围。如果上游传入的时间窗口内无数据（例如数据集是历史数据，而当前时间是现在），你**必须**调整分析窗口，使其对齐到数据集中最新的有效时间段（或数据集中包含异常的时间段）。
  - **逆序分析原则**：对于“刚刚/最近”发生的故障，在分析数据时，**必须从时间窗口的末尾（最新的时间）开始向前扫描**。不要因为数据开头有异常就过早下结论，务必确认该异常是否落在用户关注的“最近”时段内。
  - 如果工具返回空数据，请首先检查是否因时间偏差（如时区差异、数据上报延迟、历史数据集）导致。
  - 严禁分析与当前故障无关的历史异常（如发生在数小时前的错误），除非有明确证据表明它们相关。

## 依赖关系

本 Skill 通常由 `fault-intelligent-positioning` Skill 调度。

## 输入约定

- 故障时间窗口（开始时间和结束时间）
- 故障场景上下文（由上游提供）

## 输出格式

JSON 列表，包含候选故障组件：
```json
[
  {
    "component_name": "组件名称",
    "faulty_kpi": "关键指标名称",
    "fault_start_time": "ISO时间",
    "severity_score": 0.0
  }
]
```

## 可用工具与调用方式

**优先使用原则**：请优先使用scripts里面提供的工具进行数据查询和分析。只有当这些脚本执行失败、返回空结果或明确无法满足需求时，才考虑使用其他系统命令（如 `grep` 等）直接操作数据文件。

所有指标分析能力通过同一个 Python 脚本提供：

- 脚本路径：`.claude/skills/fault-delimitation/scripts/metric_tool.py`
- 基本调用形式：

```bash
python .claude/skills/fault-delimitation/scripts/metric_tool.py <command> --start <开始时间> --end <结束时间> [其他参数]
```

时间相关参数：
- `--start` / `--end`：ISO8601 格式时间（例如 `2024-01-01T00:00:00`）。
- 时区：使用场景配置（OpenRCA 默认 `Asia/Shanghai`，即 UTC+8）。

可用子命令及功能说明如下（模型可自行组合调用）：

- `entities`
  - 功能：返回在指定时间窗口内存在监控数据的实体（机器/服务等）列表。
  - 主要参数：
    - `--start`：开始时间。
    - `--end`：结束时间。

- `metrics`
  - 功能：返回可用指标名称列表，可按实体和名称模式过滤。
  - 主要参数：
    - `--start`：开始时间。
    - `--end`：结束时间。
    - `--entity`：可选，实体 ID（如 `apache01`），仅返回该实体的指标。
    - `--pattern`：可选，按名称模式过滤指标（如 `cpu`、`latency`）。
    - `--top`：可选，返回的指标数量上限，默认 10。

- `detect`
  - 功能：在指定时间窗口内执行指标异常检测，输出异常实体+指标的候选集合。
  - 主要参数：
    - `--start`：开始时间。
    - `--end`：结束时间。
    - `--method`：异常检测方法，`ruptures`、`zscore` 或 `both`，默认 `both`。
    - `--top`：返回的异常记录数量上限，默认 10。

- `suspicious`
  - 功能：根据指标异常自动识别可疑组件及其关键异常指标，返回符合“输出格式”一节定义的 JSON 列表。
  - 主要参数：
    - `--start`：开始时间。
    - `--end`：结束时间。
    - `--method`：异常检测方法，`ruptures`、`zscore` 或 `both`，默认 `both`。
    - `--top`：返回的可疑组件数量上限，默认 10。

- `get_metric_statistics`
  - 功能：对单个组件的单个指标进行统计分析，返回均值、分位数、非零比例等详细统计信息。
  - 主要参数：
    - `--start`：开始时间。
    - `--end`：结束时间。
    - `--component`：组件名称（例如 `Tomcat01`）。
    - `--metric`：指标名称（例如 `OSLinux-CPU_CPU_CPUCpuUtil`）。

- `compare_entity_metrics`
  - 功能：对单个实体在目标窗口与基线窗口之间的多个指标进行对比，给出均值和 p99 的变化情况。
  - 主要参数：
    - `--start`：目标窗口开始时间。
    - `--end`：目标窗口结束时间。
    - `--entity`：实体 ID。
    - `--metric-names`：可选，逗号分隔的指标名列表；若提供，则优先使用。
    - `--pattern`：可选，指标名称过滤模式（在未提供 `--metric-names` 时生效）。
    - `--baseline-start`：可选，基线窗口开始时间；未提供时自动推断。
    - `--baseline-end`：可选，基线窗口结束时间；未提供时自动推断。

- `find_metric_outliers`
  - 功能：基于 Z-score 在多个实体和指标上查找离群点，输出最异常的若干条记录。
  - 主要参数：
    - `--start`：开始时间。
    - `--end`：结束时间。
    - `--metric-selector`：可选，指标选择器；可以是正则模式，或逗号分隔的多个指标名。
    - `--z-threshold`：Z-score 阈值，默认 3.0。
    - `--min-points`：每个时间序列的最小点数，默认 5。
    - `--limit`：返回的最大离群点条数，默认 10。

### 日志分析工具（log_tool.py）

- 脚本路径：`.claude/skills/fault-delimitation/scripts/log_tool.py`
- 基本调用形式（工程根目录执行）：

```bash
python .claude/skills/fault-delimitation/scripts/log_tool.py <command> \
  --start <开始时间> \
  --end   <结束时间> \
  --dataset-path <数据集路径> \
  --timezone <时区> \
  [其他参数]
```

通用参数（**必须显式指定，以确保上下文正确**）：
- `--start` / `--end`：ISO8601 格式时间，例如 `2021-03-04T01:00:00`。
- `--dataset-path`：对应场景的数据集根目录绝对路径。
  - **重要约束**：
    1. 路径必须指向**具体场景目录**（例如 `datasets/DiskFault`）。
    2. **严禁**指向父目录（如 `datasets`）。
    3. **严禁**指向场景内的日期子目录（如 `DiskFault/2024-05-20`）。
- `--timezone`：数据集对应的时区，例如 `Asia/Shanghai` 或 `UTC`。

可用子命令及功能：

- `summary`
  - 功能：统计时间窗口内日志总量、实体数量、错误数量等，给出整体日志活动概览。
  - 参数：
    - `--start`：开始时间。
    - `--end`：结束时间。
    - `--entity`：可选，按实体 ID 过滤。

- `query`
  - 功能：按时间、实体和内容模式查询原始日志条目，返回多条格式化日志。
  - 参数：
    - `--start`：开始时间。
    - `--end`：结束时间。
    - `--entity`：可选，实体 ID。
    - `--pattern`：可选，日志内容匹配模式（正则，大小写不敏感）。
    - `--limit`：返回日志条目数量上限，默认 20。

- `templates`
  - 功能：在时间窗口内使用 Drain3 挖掘日志模板，统计每个模板出现频次，可选返回参数示例。
  - 参数：
    - `--start`：开始时间。
    - `--end`：结束时间。
    - `--entity`：可选，实体 ID。
    - `--top-n`：返回模板数量上限，默认 50。
    - `--min-count`：模板最小出现次数阈值，默认 2。
    - `--config-path`：可选，Drain3 配置文件路径。
    - `--include-params`：是否输出参数示例（布尔开关）。
    - `--model-path`：可选，预训练 Drain3 模型路径。

### Trace 分析工具（trace_tool.py）

- 脚本路径：`.claude/skills/fault-delimitation/scripts/trace_tool.py`
- 基本调用形式（工程根目录执行）：

```bash
python .claude/skills/fault-delimitation/scripts/trace_tool.py <command> \
  --start <开始时间> \
  --end   <结束时间> \
  --dataset-path <数据集路径> \
  --timezone <时区> \
  [其他参数]
```

通用参数（**必须显式指定，以确保上下文正确**）：
- `--start` / `--end`：ISO8601 格式时间。
- `--dataset-path`：对应场景的数据集根目录绝对路径。
  - **重要约束**：
    1. 路径必须指向**具体场景目录**（例如 `datasets/DiskFault`）。
    2. **严禁**指向父目录（如 `datasets`）。
    3. **严禁**指向场景内的日期子目录（如 `DiskFault/2024-05-20`）。
- `--timezone`：数据集对应的时区。

可用子命令及功能：

- `find_slow_spans`
  - 功能：在时间窗口内查找耗时超过阈值的慢 span，用于识别性能热点。
  - 参数：
    - `--start`：开始时间。
    - `--end`：结束时间。
    - `--entity`：可选，实体 ID。
    - `--min-duration-ms`：最小时长阈值（毫秒），默认 1000。
    - `--limit`：返回 span 数量上限，默认 10。

- `analyze_trace_call_tree`
  - 功能：针对单个 trace，输出调用树结构和各节点耗时。
  - 参数：
    - `--trace-id`：Trace ID。
    - `--start`：用于定位该 trace 的开始时间。
    - `--end`：用于定位该 trace 的结束时间。

- `get_dependency_graph`
  - 功能：基于 Trace 推导实体依赖关系，统计调用次数，形成依赖图。
  - 参数：
    - `--start`：开始时间。
    - `--end`：结束时间。
    - `--entity`：可选，仅关注某个实体相关的依赖边。

- `detect_anomalies_zscore`
  - 功能：使用 Z-Score 在 Trace 时延上检测异常，返回异常 span 列表。
  - 参数：
    - `--start`：开始时间。
    - `--end`：结束时间。
    - `--entity`：可选，实体 ID。
    - `--sensitivity`：灵敏度（0.0–1.0），默认 0.8。

- `identify_bottlenecks`
  - 功能：按实体汇总 Trace 时延，识别对整体延迟贡献度最高的瓶颈服务。
  - 参数：
    - `--start`：开始时间。
    - `--end`：结束时间。
    - `--min-impact-percentage`：最小影响占比阈值（百分比），默认 10.0。

- `train_iforest_model`
  - 功能：在指定时间段上训练 Isolation Forest 模型，学习服务调用时延的正常模式。
  - 参数：
    - `--start`：训练数据开始时间。
    - `--end`：训练数据结束时间。
    - `--save-path`：可选，模型保存路径。

- `detect_anomalies_iforest`
  - 功能：使用训练好的 Isolation Forest 模型在新时间窗口内检测 Trace 异常。
  - 参数：
    - `--start`：分析开始时间。
    - `--end`：分析结束时间。
    - `--model-path`：可选，模型加载路径；未提供时使用内存中的模型。
