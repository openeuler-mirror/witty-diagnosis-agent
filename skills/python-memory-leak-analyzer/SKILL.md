---
name: python-memory-leak-analyzer
description: >
  Python 进程内存泄漏根因分析技能。当用户提到 Python 服务或脚本 RSS 持续上涨、
  内存降不下来、疑似 memory leak、被 OOM kill、缓存持续膨胀、tracemalloc/gc 线索、
  已有 memray 产物、C 扩展或 native 内存增长时，必须使用本技能。覆盖 Python
  托管对象泄漏、全局容器/无界缓存、闭包/回调/线程局部保留、引用循环、分配点与保留点分离、
  RSS 与 Python 堆背离、碎片化或缓存预热伪泄漏。支持从目录、PID、服务名或日志包自动发现证据。
  默认采用只读和可复现路径，不默认 attach 线上进程或执行副作用干预。
---

# Python 内存泄漏根因分析 Skill

## 第一节：使用时机与输入

当问题涉及 Python 进程内存持续增长、RSS 居高、OOM、疑似泄漏、native/C 扩展内存、mmap/file/shmem 增长或“内存降不下来”时使用本 skill。用户只给目录、PID、服务名、日志包或模糊范围时，先自动发现证据，不要求用户手工枚举 JSON 或日志。

可接受输入：

- 目录、日志包、测试输出目录、报告目录或源码范围。
- PID、服务名、容器名、cgroup 线索。
- 可复现 workload 脚本，要求定义 `run_workload(iterations)`，可选 `setup()`。
- 已有 `tracemalloc`、memray、RSS、OOM、monitor、`/proc` 或 Witty 报告产物。

本 skill 内置脚本：

```text
scripts/
├── detect_capabilities.py
├── discover_evidence.py
├── live_process_snapshot.py
├── monitor_rss.py
├── object_growth.py
├── semantic_probe.py
├── tracemalloc_probe.py
├── retention_chain.py
├── reachability_probe.py
├── correlate_evidence.py
└── parse_memray.py
```

## 第二节：核心原则

- **范围先行**：先确认当前诊断范围、PID、worker、cgroup 和 mapping 口径；历史报告不能替代当前范围内的结构化证据。
- **先判内存表面再归因**：RSS 高水位、短窗口、缓存预热、allocator high-water、mmap/file/shmem 或 worker skew 都可能不是 Python retained leak；先读 `correlation.json.summary.memory_surface`，再判断 Python heap、native allocator 或 file/shmem/mmap 方向。
- **分配点不等于根因**：tracemalloc 只回答“在哪里分配”，根因通常在保留者和生命周期缺陷。
- **报告前必须对账**：最终结论先读 `correlation.json`，再按 `references/evidence-analysis.md` 和 `references/validation-gates.md` 控制措辞。
- **线上默认只读**：不默认 attach、ptrace、安装依赖、清缓存、置空全局、注销回调、重启或修改配置。

## 第三节：统一流程

### 1. 运行边界预检

```bash
python scripts/detect_capabilities.py
```

读取 `runtime`、`proc`、`cgroup`、`readonly_boundary` 和 `recommended_path`。该脚本只描述当前证据采集环境的 `/proc`、`smaps_rollup`、cgroup 和 ptrace 边界，不探测第三方库，也不生成外部依赖清单。
如果当前输入是离线证据目录或已生成的测试输出，目录内的 `capabilities.json` 只作为运行边界证据读取；不得把它扩展成“工具缺失”清单。
如果证据目录内存在 `report-contract.md`，它是最终报告验收门，不是根因线索；最终 Markdown 必须满足证据边界和 HTML 同源要求，再交给 `report_visualization` 生成 HTML。

### 2. 范围定界与证据发现

```bash
python scripts/discover_evidence.py /path/to/scope
python scripts/discover_evidence.py pid:<PID>
python scripts/discover_evidence.py service-or-process-name
```

按 `recommendation.recommended_path` 路由：

- `offline_evidence_bundle`：进入 `primary_evidence_dir` 读结构化证据。
- `reproducible_workload`：运行完整 Python heap 路径。
- `live_pid_external_readonly`：只做 PID/RSS/mapping/cgroup 定界；没有 heap/retention 证据不得确认 Python 根因。
- `correlated_evidence_bundle`：先读 `correlation.json`。
- `diagnosis_report`：只作背景，必须与当前场景结构化证据一致才可引用。

故障时间窗口不是离线证据包的阻塞条件；缺失时在报告中列为上下文缺口。

### 3. 采集证据

真实 PID 或服务名：

```bash
python scripts/live_process_snapshot.py --pid <PID> --output live_process_snapshot.json
python scripts/monitor_rss.py --pid <PID> --interval 1 --duration 30 --output monitor_rss_pid.json
```

可复现 workload：

```bash
python scripts/object_growth.py --script /path/to/leak_case.py --iterations 1000 --output object_growth.json
python scripts/semantic_probe.py --script /path/to/leak_case.py --iterations 1000 --output semantic.json
python scripts/tracemalloc_probe.py --script /path/to/leak_case.py --iterations 1000 --nframe 15 --output tracemalloc.json
python scripts/retention_chain.py --script /path/to/leak_case.py --iterations 1000 --type-filter "<candidate>" --output retention.json
```

生产或非沙箱环境只做静态可达性：

```bash
python scripts/reachability_probe.py --script /path/to/leak_case.py --type-filter "<candidate>" --output reachability_static.json
```

只有用户明确确认沙箱或可承受副作用时，才允许 `--allow-mutation`。

### 4. 分析证据

报告前运行或读取 evidence correlation：

```bash
python scripts/correlate_evidence.py \
  --monitor monitor_rss_pid.json \
  --snapshot live_process_snapshot.json \
  --object-growth object_growth.json \
  --tracemalloc tracemalloc.json \
  --semantic semantic.json \
  --retention retention.json \
  --output correlation.json
```

随后按顺序读取：

1. `correlation.json`：以 `verdict`、`confidence_cap` 和 `missing_evidence` 作为根因措辞总闸门。
2. 当前证据目录的 `capabilities.json`：只确认 `/proc`、`smaps_rollup`、cgroup 和 ptrace 只读边界。
3. `references/evidence-analysis.md`：证据读取顺序、字段判读、竞争假设矩阵和 verdict 措辞。
4. `references/root-cause-patterns.md`：把 semantic label 与 root_kind 映射到根因模式。
5. `references/validation-gates.md`：填写 G0-G5，确定 confirmed/strong/weak/direction-only。
6. `references/native-leaks.md` 或 `references/live-process.md`：处理 native/mmap/allocator 或只读 PID 边界。

禁止绕过 `correlation.json` 直接写“已确认 Python 根因”。`readonly_insufficient`、`native_or_allocator_suspect`、`mmap_or_file_backed_growth`、`allocator_reuse_or_fragmentation_possible` 只能输出方向级或边界结论。若 `memory_surface.primary_surface` 指向 `file_backed`、`shmem` 或 `mmap_or_file_backed`，先说明 RSS 增长表面和证据来源，再讨论是否仍需要 Python heap、native allocator 或业务 mmap 证据。

## 第四节：报告要求

### 1. 通用 RCA 与 HTML 生成

最终报告默认采用 `skills/fault-rca-report-generation/SKILL.md` 的通用 RCA 模板；H1、二级标题和基础章节以通用 RCA 为准。

最终 Markdown 是 HTML 的唯一来源。使用 Witty 原配 `report_visualization` 生成 HTML 时，Markdown 与 HTML 必须使用同一 basename，并包含场景名和完整时间戳或会话标识；若同名旧报告已存在，写入新的唯一文件名，不覆盖、不复用历史报告。

诊断质量检查是生成前的内部动作，不写入最终 Markdown 或 HTML。

### 2. Python 内存领域必含内容

Python 内存泄漏报告必须在通用 RCA 结构内覆盖以下领域内容，可放在“排查过程”“根因速览”或领域深度分析章节下，不要求固定为独立二级标题：

- Live PID 只读定界。
- 证据对账总闸门。
- RSS 与增长形态，包括 `memory_surface` 主导内存表面。
- Python 对象增长、语义保留信号、分配热点和保留链。
- 验证门与竞争假设。
- 根因结论、修复建议和复测方案。

### 3. 证据与边界

最终报告应包含短小的“证据与边界”内容，可使用独立二级标题 `## 证据与边界`，也可并入通用 RCA 的证据或排查章节。该内容只写最终读者需要看到的边界：

- 已读取的证据文件或证据目录。
- `correlation.json` 的 `verdict`、`confidence_cap` 和 `missing_evidence`。
- `correlation.json.summary.memory_surface` 的主导内存表面；file/shmem/mmap 表面只能作为方向级结论，除非另有 mmap 文件、fd、业务 owner 或 native 采集证据。
- 只读边界：未执行 attach/ptrace、未执行修复、未重启服务、未修改配置或未运行副作用反事实。
- 缺失证据对结论和置信度的影响。

### 4. 结论措辞与置信度

报告必须明确区分：

- 已确认事实。
- 主导假设。
- 次要来源或干扰项。
- 未验证项。
- 因权限、线上风险或证据缺失导致的置信度上限。

低证据、RSS-only、PID-only、`readonly_insufficient` 或 `direction-only` 场景仍要写清证据与边界。这类场景重点说明：实际只有外部 RSS、`/proc`、日志或 `correlate_evidence.py` 对账；缺少 `object_growth.json`、`tracemalloc.json`、`semantic.json`、`retention.json` 或 live snapshot 是证据缺口和置信度封顶原因，不是“工具不可用”。

诊断状态与修复状态必须分开。只读诊断完成只能写“诊断完成”“根因已定位”或“修复建议已给出”，不得写“已恢复”“已修复”或“故障已恢复”。只有获得修复授权、执行修复动作并完成复测后，才可声明已恢复。

### 5. 工具与升级建议

外部工具不进入默认报告验收。已有 memray capture/report 可以用 `parse_memray.py` 解析；native/allocator 深挖需要额外采集 native allocation stack、allocator stats、C 栈符号或 mmap owner 线索时，只能作为单独授权的升级建议写入后续验证，不作为默认依赖。

缺失证据只按证据类型描述，不按可选工具或依赖描述。可选增强工具不列入报告验收表、能力表或缺失证据表，也不作为最终结论的必要前提。

推荐证据边界写法：

- “缺少 native allocation stack 或 allocator stats，native/allocator 只能保持方向级结论。”
- “缺少 Python heap 快照、语义保留信号或保留链，不能确认 Python retained leak。”
- “如需进一步验证，可在单独授权后采集 native allocation 或 C 栈证据。”

### 6. 生成前验收门

最终报告生成前执行以下验收门：

1. 打开本轮 `correlation.json`；若不存在，说明未运行对账并保持结论降级。
2. 如果本轮证据目录存在 `report-contract.md`，逐条核对其中的 HTML 同源和证据边界要求。
3. 在生成 HTML 之前检查最终 Markdown；若缺少证据边界、越过 `confidence_cap`，或把缺失证据写成缺少工具，必须先修正文档。
4. 确认修复建议与已执行动作已明确区分，HTML 由同一份本轮 Markdown 生成且 basename 一致。

低输入或只读验证场景中，不要在报告尾部发起“是否执行修复”的交互选择；自动源码修复和修复后验证需要独立授权。修复建议必须作为建议或后续操作呈现；如果本轮没有执行修复，不得把清空容器、重启进程、修改代码、attach/ptrace 或配置写入描述为已执行动作。

## 第五节：安全边界

- 只读或离线解析：`detect_capabilities.py`、`discover_evidence.py`、`live_process_snapshot.py`、`monitor_rss.py`、`correlate_evidence.py`、`parse_memray.py`。
- 会执行 workload：`object_growth.py`、`semantic_probe.py`、`tracemalloc_probe.py`、`retention_chain.py`。仅用于可信离线样例、测试目录或用户确认的沙箱复现。
- 有副作用：`reachability_probe.py --allow-mutation`，只能在沙箱或用户明确批准的可承受环境执行。
- 线上 PID 默认不 attach、不 ptrace、不安装包、不清缓存、不置空全局、不注销回调、不重启服务。

## 第六节：参考文件

- `references/methodology.md`：阶段化方法论。
- `references/evidence-analysis.md`：证据判读、竞争假设和结论措辞。
- `references/tool-selection.md`：核心路径和可选升级。
- `references/validation-gates.md`：G0-G5 可填写验证门。
- `references/root-cause-patterns.md`：常见根因模式卡片。
- `references/live-process.md`：线上不可重启 PID 边界。
- `references/native-leaks.md`：native、allocator、mmap 与 Python 堆背离路径。
