---
name: python-memory-leak-analyzer
description: >
  Python 进程内存泄漏根因分析技能。当用户提到 Python 服务或脚本 RSS 持续上涨、
  内存降不下来、疑似 memory leak、被 OOM kill、缓存持续膨胀、tracemalloc 线索、
  gc/objgraph/memray 诊断、C 扩展或 native 内存增长时，必须使用本技能。覆盖 Python
  托管对象泄漏、全局容器/无界缓存、闭包/回调/线程局部保留、引用循环、分配点与保留点分离、
  RSS 与 Python 堆背离、碎片化或缓存预热伪泄漏。支持从目录、PID、服务名或日志包自动发现证据。
  首版默认只读和可复现路径，不默认 attach 线上进程或执行副作用干预。
---

# Python 内存泄漏根因分析 Skill

## 第一节：故障目录结构

```text
python_memory_leak_case/
├── workload/                    # 可选：复现脚本、应用入口或最小 workload
│   └── leak_case.py             # 定义 run_workload(iterations)
├── logs/                        # 可选：OOM 日志、监控曲线、应用日志
├── snapshots/                   # 可选：tracemalloc/memray/监控快照
└── reports/                     # 输出：诊断报告和证据 JSON
```

本 skill 内置脚本位于：

```text
skills/python-memory-leak-analyzer/
├── config.py
├── scripts/
│   ├── detect_capabilities.py
│   ├── discover_evidence.py
│   ├── live_process_snapshot.py
│   ├── monitor_rss.py
│   ├── correlate_evidence.py
│   ├── object_growth.py
│   ├── semantic_probe.py
│   ├── tracemalloc_probe.py
│   ├── retention_chain.py
│   ├── reachability_probe.py
│   └── parse_memray.py
├── references/
└── assets/report-template.md
```

---

## 第二节：分析策略（症状定界 + 分配线 + 保留线）

Python 内存泄漏诊断不能停在 “RSS 涨了” 或 “tracemalloc 某行分配多”。必须区分三件事：

| 层级 | 回答的问题 | 主要证据 |
| --- | --- | --- |
| 范围层 | 是否看对 PID、worker、cgroup 和 mapping 口径 | `live_process_snapshot.py`、`discover_evidence.py` |
| 症状层 | RSS/Private_Dirty/cgroup 是否持续增长，是否 plateau，是否接近 OOM | `monitor_rss.py`、OOM 日志、cgroup memory |
| 分配线 | 内存在哪里被分配 | `tracemalloc_probe.py`、可选 memray |
| 保留线 | 为什么对象仍然可达、谁持有它 | `object_growth.py`、`semantic_probe.py`、`retention_chain.py`、`reachability_probe.py` |
| 对账层 | Python heap、native/allocator、mmap/file/shmem 是否能解释增长 | `correlate_evidence.py` |

核心原则：

- **低输入优先自动发现**：用户只给出“分析 Python 泄露问题”和目录、PID、服务名或大概范围时，先用 `discover_evidence.py` 找日志、快照、workload、报告和证据目录，再决定分析路径；不得要求用户手工枚举每个 JSON 或日志。
- **当前范围隔离**：一次诊断只分析用户本轮给出的故障范围，或 `discover_evidence.py` 在该范围内发现的 `primary_evidence_dir`。历史 Witty 输出目录、归档报告目录或上一次场景报告不能替代本轮结构化证据；历史报告只能用于归档、核验或用户明确指定的对照。
- **先确认目标口径**：真实 PID 场景必须先确认 PID、进程树、cgroup、worker 和 mapping 范围；父进程稳定但 worker/cgroup 增长时，不能把 master PID 的 RSS 当成服务总内存根因。
- **时间窗口不阻塞离线证据包分析**：用户未提供故障时间时，不要停下来追问；先用 `discovery.json`、`metadata.json`、日志和证据文件时间作为“证据时间”，在报告中写明“故障时间窗口未提供/由证据生成时间近似”。只有需要从海量系统日志中按时间过滤且范围内没有可用证据时，才追问时间窗口。
- **RSS 增长不等于 Python 对象泄漏**：先排除缓存预热、allocator arena 不归还 OS、短窗口噪声和 native/C 扩展增长。
- **分配点不等于根因**：tracemalloc 只回答“在哪创建”，根因通常在“为什么还被引用”。
- **验证门在结论前**：主候选必须经过 G0 目标范围确认、G1 量化对账、G2 竞争假设排除、G3 可达性反事实或静态论证，再写根因。
- **对账总闸门优先**：报告前必须运行或读取 `correlation.json`；没有 heap/retention 证据时不能确认 Python 根因，RSS 与 Python 堆背离时必须输出 native/allocator/mmap 方向和置信度上限。
- **线上默认只读**：不默认 attach、ptrace、安装依赖、清缓存、置空全局、重启或改配置。

---

## 第三节：统一分析流程

### Step 1：启动（能力预检 + 范围定界 + 证据发现）

先运行能力探测，不等待用户确认，按当前可用能力继续分析：

```bash
python scripts/detect_capabilities.py
```

输出中重点阅读：

- `capabilities.modules`：`psutil`、`objgraph`、`pympler`、`memray` 是否可用。
- `capabilities.proc`：`/proc`、`smaps_rollup`、ptrace 默认状态。
- `recommended_path`：当前环境建议路径。
- `degraded_capabilities`：本轮置信度边界。

随后完成范围定界和证据发现。只要用户给的是目录、PID、服务名、容器名、日志包或大概范围，就先自动发现证据，再分析；不要把“请提供日志路径、JSON 路径、tracemalloc 路径”作为首轮回复。

先锁定本轮 `current_scope`：

- 用户给出目录或日志包时，`current_scope` 就是该路径；根因证据必须来自该目录内部，或来自 `discovery.json` 指向且仍位于该目录内部的 `primary_evidence_dir`。
- 用户给出 PID 或服务名时，先用 `discover_evidence.py pid:<PID>` 或 `discover_evidence.py <service-name>` 定位进程和只读证据入口；没有用户批准时只做外部观测。
- 若扫描到历史诊断报告，只把它列为 context/report artifact；它不能替代本轮 `semantic.json`、`object_growth.json`、`retention.json`、`tracemalloc.json`、`monitor_rss_pid.json`、日志或 workload 证据。
- 如果报告标题、场景名、时间窗口或关键术语与 `current_scope` 明显不一致，该报告对本轮无效，必须回到当前范围重新取证。

```bash
python scripts/discover_evidence.py /path/to/scope
python scripts/discover_evidence.py pid:<PID>
python scripts/discover_evidence.py service-or-process-name
python scripts/discover_evidence.py /path/to/log-or-test-dir pid:<PID>
```

如果用户没有给出明确路径，但当前工作区存在测试或日志目录，先运行：

```bash
python scripts/discover_evidence.py .
```

同时优先检查当前目录、`logs/`、`out/`、`reports/`、`snapshots/`、`test/` 中最相关的 Python memory leak 目录。不要要求用户逐个列出 JSON 或日志文件。

自动发现对象包括：

```text
PID / 服务名 / 容器名
logs/、out/、reports/、snapshots/ 下的 OOM、RSS、monitor、tracemalloc、memray 文件
可复现 Python 脚本、测试 run.sh、requirements、pyproject.toml 或应用入口
```

读取 `discover_evidence.py` 输出：

- `recommendation.recommended_path`
- `recommendation.primary_evidence_dir`
- `candidate_evidence_dirs[].role_summary`
- `candidate_evidence_dirs[].key_files`
- `pid_scopes[]` 和 `process_scopes[]`

按发现结果选择路径：

| 可发现输入 | 首选动作 | 结论边界 |
| --- | --- | --- |
| `live_pid_external_readonly` 或只有 PID/RSS 日志 | 运行/读取 `live_process_snapshot.py` 和 `monitor_rss.py` 证据 | 只能确认范围和增长形态，不能确认 Python 根因 |
| `correlated_evidence_bundle` | 先读 `correlation.json`，再回看 snapshot、monitor、heap、retention 证据 | 最终报告必须引用 verdict 和 confidence_cap |
| `reproducible_workload` | 按 discovery 的 workload 路径运行 `object_growth.py`、`semantic_probe.py`、`tracemalloc_probe.py`、`retention_chain.py` | 可形成 Python 层主导假设 |
| `offline_evidence_bundle` | 进入 `primary_evidence_dir`，先读 `discovery.json`/`semantic.json`，再读 `object_growth.json`、`retention.json`、`tracemalloc.json` | 能直接离线分析，少问问题 |
| `logs_only_or_external_rss` | 读日志和 monitor 证据，判断增长形态和缺口 | 置信度封顶，不能强行确认根因 |
| 有 memray capture/report | 运行 `parse_memray.py` 或建议 memray reporter | native/Python allocation 方向增强 |
| 只有源码范围 | 静态检查全局容器、无界缓存、registry、闭包、线程局部和未关闭 generator/task | 只能输出待验证假设 |

如果范围内已有 `discovery.json`，先读取它并复核 `primary_evidence_dir` 下的实际文件；如果没有，就运行 `discover_evidence.py` 生成本轮发现结果。发现到 `offline_evidence_bundle` 或 `reproducible_workload` 时，直接进入后续证据分析，不再追问日志路径。

`discovery.initial.json` 或带有初始扫描语义的发现文件只表示证据生成前的第一轮范围扫描。它不能覆盖最终 `discovery.json` 的推荐，也不能作为最终根因分析的主证据入口；最终分析仍以当前范围目录实际存在的 `semantic.json`、`object_growth.json`、`retention.json`、`tracemalloc.json`、`monitor_rss_pid.json` 和日志为准。

`diagnosis_report` 或历史 Markdown/HTML 报告不是主证据入口。只有当报告位于 `current_scope` 内、明显属于当前场景，且与本轮结构化证据一致时，才能作为背景引用；若结构化证据和历史报告冲突，优先相信当前范围内的结构化证据，并在报告中说明冲突。

只在自动发现后仍缺少关键边界时追问最少问题：故障范围、是否允许重启复现、是否允许安装工具、是否允许 attach/ptrace、是否是沙箱环境。线上或不明确环境默认只读。

不要把“故障时间窗口”列为 `offline_evidence_bundle`、`reproducible_workload` 或 `live_pid_external_readonly` 的首轮阻塞问题。范围内已有 `metadata.json`、`discovery.json`、`*.log` 或结构化证据时，时间只用于报告时间线标注；缺失时写入未验证项，继续完成根因定界和证据链分析。

### Step 1.5：Live PID 只读预检

已有真实 PID、服务名已解析到 PID、或用户要求线上无副作用验证时，先做只读预检：

```bash
python scripts/live_process_snapshot.py --pid <PID> --output live_process_snapshot.json
python scripts/live_process_snapshot.py --pid <PID> --detail-smaps --top 20 --output live_process_snapshot.json
```

默认只读取 `/proc/<pid>/status`、`smaps_rollup`、`maps`、`cgroup`、子进程、线程数、fd 数和 cgroup memory events；不读取完整 `smaps`。只有需要定位 top mapping 且能接受较高读取开销时才加 `--detail-smaps`。

重点读取：

- `process_scope`：PID、PPID、cmdline、exe、cwd、线程数、fd 数。
- `children_summary`：是否存在 pre-fork worker 或子进程内存超过 master。
- `cgroup_scope`：memory.current/memory.usage_in_bytes 是否来自目标 PID 所在 cgroup。
- `memory_breakdown`：RSS、RssAnon、RssFile、RssShmem、Private_Dirty。
- `mapping_summary`：anonymous、heap、file_backed、shmem_or_memfd、deleted_file 等 mapping 组成。
- `readonly_verdict.confidence_cap`：只读 PID 只能定界；没有 Python heap/retention 证据不能确认 Python 对象根因。

如果 `readonly_verdict.flags` 包含 `children_memory_exceeds_target_pid`、`process_tree_present`、`file_or_shmem_dominant_rss` 或 `deleted_file_mapping_present`，后续报告必须先处理 scope/mapping 竞争假设。

### Step 2：症状定界与伪泄漏证伪

已有 PID 时做外部只读观测：

```bash
python scripts/monitor_rss.py --pid <PID> --interval 1 --duration 30
```

可重启复现时从进程出生开始观测：

```bash
python scripts/monitor_rss.py --cmd "python /path/to/app.py" --interval 1 --duration 30
```

判断：

| `summary.verdict` | 处理 |
| --- | --- |
| `target_pid_growth` | 继续 Step 3，用 Python 堆证据归因 |
| `cgroup_growth_not_target` | 目标 PID 不能解释容器内存，扩大到 cgroup 或 sibling 进程 |
| `worker_skew_growth` | master 稳定但 worker 增长，切换到增长 worker PID |
| `file_or_shmem_growth` | 优先排查 mmap/file/shmem，不确认 Python 对象泄漏 |
| `plateau_high_water` | 优先判为预热、缓存填充或 allocator 不归还 OS；除非后续谷值继续抬升 |
| `insufficient_window` | 延长采样或补充工作负载、OOM 时间窗口、cgroup 指标 |

若 RSS 增长明显但后续 `object_growth.py` 与 `tracemalloc_probe.py` 无法解释主要增长，转 `references/native-leaks.md`。

### Step 3：定位“什么在涨”

可复现 workload 必须定义 `run_workload(iterations)`；可选定义 `setup()`。示例：

```python
LEAK = []

def run_workload(iterations):
    for i in range(iterations):
        LEAK.append({"i": i, "payload": "x" * 1024})
    return len(LEAK)
```

运行对象增长分析：

```bash
python scripts/object_growth.py --script /path/to/leak_case.py --iterations 1000
```

重点读取：

- `summary.verdict`
- `summary.primary_candidate`
- `type_growth`
- `big_containers_after`

主候选若只解释很小增量，不得直接下根因，应回到 workload 或 RSS 对账找更大来源。

### Step 4：盘点语义信号

可复现 workload 下运行：

```bash
python scripts/semantic_probe.py --script /path/to/leak_case.py --iterations 1000
```

优先读取：

- `summary.dominant_signals`
- `global_semantics`
- `cache_semantics`
- `gc_semantics`

`semantic_probe.py` 用于把复杂保留模式变成可读证据，例如：

| label | 解释 |
| --- | --- |
| `global_registry_retains_bound_methods` | 全局 registry/list 保存 bound method，间接持有实例 |
| `global_table_retains_closures` | 全局表保存闭包函数，closure cell 持有 payload |
| `unbounded_cache_growth` | callable cache 的 `currsize` 增长且 `maxsize=None` |
| `unclosed_generators_retain_frames` | 未关闭 generator 保留 frame locals |
| `pending_asyncio_tasks_retain_frames` | pending task 保留 coroutine frame locals |
| `weakref_finalize_callbacks_retained` | `weakref.finalize` 或回调对象被全局结构保留 |

多源场景必须比较 `dominant_signals` 的 score 和增量，不得把显眼但增量很小的 global 当作唯一确认根因。

### Step 5：追分配线

```bash
python scripts/tracemalloc_probe.py --script /path/to/leak_case.py --iterations 1000 --nframe 15
```

输出 `alloc_growth` 是分配热点，只能作为分配证据。必须与 Step 3 增长类型、Step 4 语义信号和 Step 6 保留链交叉验证。

### Step 6：追保留线

将 Step 3 的 `primary_candidate` 传入：

```bash
python scripts/retention_chain.py \
  --script /path/to/leak_case.py \
  --iterations 1000 \
  --type-filter "builtins.dict"
```

或用类型名子串：

```bash
python scripts/retention_chain.py --script /path/to/leak_case.py --name-contains "MyObject"
```

读取：

- `root_kind_summary`
- `chains[].root_kind`
- `chains[].chain`

常见 root_kind 解释见 `references/root-cause-patterns.md`。例如全局容器通常输出为
`module_global:<name>`。

### Step 7：验证门与反事实

生产或非沙箱环境默认只做静态可达性论证：

```bash
python scripts/reachability_probe.py \
  --script /path/to/leak_case.py \
  --type-filter "builtins.dict"
```

只有用户明确确认是测试/沙箱且允许副作用时，才执行反事实干预：

```bash
python scripts/reachability_probe.py \
  --script /path/to/leak_case.py \
  --type-filter "builtins.dict" \
  --global-name LEAK \
  --allow-mutation
```

若未设置 `--allow-mutation`，结论置信度封顶为 `weak`；若 `counterfactual_confirmed`，可把根因从主导假设提升为确认根因。

### Step 8：证据对账总闸门

在写最终报告前运行证据对账。已有哪类证据就传哪类；缺失证据不应导致失败，但会进入 `missing_evidence[]` 和 `confidence_cap`：

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

重点读取：

- `summary.verdict`
- `summary.confidence_cap`
- `summary.missing_evidence`
- `summary.python_heap_to_private_dirty_ratio`
- `summary.tracked_object_to_private_dirty_ratio`
- `summary.tracemalloc_peak_vs_final`
- `summary.candidate_coverage_ratio`
- `summary.scope_flags`

报告措辞规则：

| `summary.verdict` | 报告边界 |
| --- | --- |
| `python_retained_leak_likely` | 只有同时存在 Python heap 对账和 semantic/retention 证据时，才能写 Python retained leak likely |
| `native_or_allocator_suspect` | 写 native/C 扩展/allocator 方向疑似，不确认 Python 对象根因 |
| `mmap_or_file_backed_growth` | 写 mmap/file/shmem 增长方向，优先引用 maps/smaps/cgroup |
| `transient_peak_not_retained` | 写峰值过高或短时 copy volume，不写最终保留泄漏 |
| `mixed_growth` | 保留 Python 与 native/mmap 混合假设，按 coverage 排序 |
| `readonly_insufficient` | 只读证据不足，置信度封顶；请求复现 workload 或 heap/retention 证据 |

### Step 9：native 或背离路径

已有 memray capture 或文本报告时：

```bash
python scripts/parse_memray.py --capture /path/to/memray-report-or-capture --top 20
```

没有 memray 或 debug symbols 时，不要假装能定位 C 栈根因；报告应写成 “RSS 与 Python 堆背离，native/allocator 方向疑似”，并列出下一步采集建议。

---

## 第四节：验证门

| 验证门 | 通过条件 | 不通过时 |
| --- | --- | --- |
| G0 目标范围和口径确认 | PID、process tree、cgroup、worker 和 mapping 口径一致；或明确说明 scope mismatch | 不能进入根因确认，只能做只读定界 |
| G1 量化对账 | 主候选解释主要增长，或说明为何只能方向级判断 | 回 Step 3/4/5 找更大来源 |
| G2 竞争假设 | 至少排除预热、碎片化、native 背离、短窗口噪声 | 结论写为待验证 |
| G3 可达性 | 反事实回收成功，或静态保留链充分但置信度封顶 | 回 Step 6 找其他保留路径 |
| G4 隔离复测 | 修复/禁用候选后增长停止 | 不可行时列为验证建议 |
| G5 置信度 | 证据链、缺口和未验证项写清 | 禁止输出“已确认” |

---

## 第五节：安全边界

- 默认不修改目标系统：`detect_capabilities.py`、`discover_evidence.py`、`live_process_snapshot.py`、`monitor_rss.py`、`correlate_evidence.py`、`parse_memray.py` 是外部只读或离线解析；`object_growth.py`、`semantic_probe.py`、`tracemalloc_probe.py`、`retention_chain.py` 会执行用户提供的 workload 脚本，只能用于可信离线样例、测试目录或用户确认的沙箱复现。
- `reachability_probe.py --allow-mutation` 会清空或置空指定全局对象，只能用于测试/沙箱或用户明确批准的可承受环境。
- 不默认安装 pip 包、不默认启用 ptrace、不默认 attach 线上进程、不默认重启服务。
- 对线上进程只能先使用外部观测或既有快照；需要 py-spy/pyrasite/memray attach、进程内注入或执行生产 workload 时，必须单独说明风险并等待批准。
- 本 skill 的默认产物到“诊断结论、修复建议、复测方案”为止。低输入或只读验证场景中，不要在最终报告尾部发起“是否执行故障修复”的交互选择；自动源码修复和修复后验证属于后续独立流程。

---

## 第六节：最终报告结构

按 `assets/report-template.md` 输出，至少包含：

```text
1. 故障概要与影响
2. 能力画像与降级边界
3. Live PID 只读定界
4. 证据对账总闸门
5. RSS/堆增长定界
6. 对象增长证据
7. 语义保留信号
8. 分配热点证据
9. 保留链证据
10. 验证门结果
11. 根因结论与置信度
12. 修复建议
13. 复测方案
```

报告中必须明确区分：

- 已确认事实
- 主导假设
- 未验证项
- 因权限/依赖/线上风险导致的置信度上限

---

## 第七节：参考文件

- `references/methodology.md`：阶段化诊断方法论。
- `references/tool-selection.md`：依赖分层和环境路由。
- `references/validation-gates.md`：G0-G5 验证门。
- `references/root-cause-patterns.md`：常见 Python 泄漏模式。
- `references/live-process.md`：线上不可重启进程的边界。
- `references/native-leaks.md`：RSS 与 Python 堆背离时的 native 路径。
- `assets/report-template.md`：报告模板。
