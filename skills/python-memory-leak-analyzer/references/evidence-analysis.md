# 证据分析手册

本文件负责把脚本产物转成诊断判断。采集脚本只回答“看到了什么”，最终报告必须按本手册完成证据判读、竞争假设排除和置信度封顶。

## 1. 读取顺序

按固定顺序读证据，缺失项写入 `missing_evidence`，不要跳过对账直接下根因：

1. `discovery.json`：确认 `recommended_path`、`primary_evidence_dir`、当前范围和历史报告是否只是 context。
2. `live_process_snapshot.json` 与 `monitor_rss_pid.json`：确认 PID、worker、cgroup、mapping 和增长形态。
3. `object_growth.json`、`semantic.json`、`tracemalloc.json`、`retention.json`：分别读取对象增长、语义保留信号、分配线和保留链。
4. `correlation.json`：作为最终措辞闸门，先引用 `summary.verdict`、`confidence_cap`、`missing_evidence`，再写根因。
5. `reachability_static.json` 或 `reachability_counterfactual.json`：只用于提升或限制置信度，不能替代 G1/G2。

如果证据冲突，优先级为：当前范围内结构化 JSON > 当前日志 > 当前场景报告 > 历史报告。历史 Witty 报告不能替代当前场景证据。

## 2. 单项证据判读

### discovery

- `offline_evidence_bundle`：进入 `primary_evidence_dir`，直接读结构化证据，不追问日志文件。
- `reproducible_workload`：运行对象增长、语义、tracemalloc、保留链和 correlation。
- `live_pid_external_readonly`：只能做 PID/RSS 定界；没有 heap/retention 证据不得确认 Python 根因。
- `correlated_evidence_bundle`：先读 `correlation.json`，再回看各输入证据。
- `diagnosis_report`：只作背景；若报告标题、术语或场景与当前范围不一致，标为无效输入。

### live snapshot 与 monitor

- `target_pid_growth`：目标 PID 有增长，可以继续找 Python heap 或 native/mmap 解释。
- `cgroup_growth_not_target`：目标 PID 不能解释 cgroup 增长，报告写 scope mismatch，不能确认目标 PID 的 Python 根因。
- `worker_skew_growth`：master 稳定但 worker 增长，切换到增长 worker；不能只看 master。
- `file_or_shmem_growth`、snapshot 的 file/shmem flags，或 `correlation.json.summary.memory_surface.file_shmem_dominant=true`：优先 mmap/file/shmem 假设。
- `plateau_high_water`：优先 allocator reuse、arena、cache warmup 或 fragmentation high-water；不写 retained leak。
- `insufficient_window`：短窗口，置信度封顶；需要更长采样或 workload。

### object growth

重点读 `type_growth`、`big_containers_after`、`checkpoint_trend.summary` 和 `summary.primary_candidate`。主候选只占很小比例时，不能直接写根因；必须转到 G1 对账并保留竞争假设。

### semantic

重点读 `summary.dominant_signals`、`global_semantics`、`cache_semantics`、`gc_semantics`。多源场景按 score、len_delta、currsize_delta 和业务保留者排序；显眼的小 global 只能作为干扰项，不能自动成为主根因。

### tracemalloc

`alloc_growth` 和 top stack 只说明分配点。若分配点与 `semantic`/`retention` 的保留者不同，报告必须写“分配点不是根因，保留者才是生命周期缺陷”。

### retention

重点读 `root_kind_summary` 和 `chains[].root_kind`。多个 root_kind 发散时保留多假设，不能只挑一个最容易解释的路径。`unknown` root_kind 只能支持弱假设，除非 `semantic` 和 `correlation` 同时补足。

### correlation

最终报告必须按 `summary.verdict` 控制措辞：

| verdict | 允许措辞 |
| --- | --- |
| `python_retained_leak_likely` | 写 Python retained leak 主导假设；只有 G3/G4 通过才写确认根因 |
| `native_or_allocator_suspect` | 写 native/C 扩展/allocator 方向疑似，不确认 Python 对象泄漏 |
| `mmap_or_file_backed_growth` | 写 mmap/file/shmem 增长方向，引用 maps/smaps/cgroup |
| `allocator_reuse_or_fragmentation_possible` | 写 allocator reuse、arena、cache warmup 或 fragmentation high-water，不写 retained leak |
| `transient_peak_not_retained` | 写峰值或短时 copy volume，不写最终保留泄漏 |
| `mixed_growth` | 拆成 Python retained 与 native/mmap 两条假设，按 coverage 排序 |
| `readonly_insufficient` | 只读证据不足，置信度封顶，请求复现 workload 或 heap/retention 证据 |

`summary.coverage_warning=top_candidate_low_coverage_check_competing_semantic_and_retention_signals` 时，说明单一 `object_growth` top type 不足以独占解释增长。报告必须回看 `semantic.dominant_signals` 和 `retention.root_kind_summary`，把更强的保留者排在前面，并把小 global、debug 容器或浅层类型写成干扰项或次要来源。

## 3. 竞争假设矩阵

最终报告至少填写下列假设中的相关项：

| 假设 | 支持证据 | 反证或降级条件 | 结论边界 |
| --- | --- | --- | --- |
| Python retained leak | heap/tracked object ratio 高，且 semantic/retention 命中 | 无 retention、coverage 低、G3/G4 未做 | 主导假设或 confirmed |
| native/allocator | RSS/Private_Dirty 增长但 Python heap ratio 低，且 memory_surface 未指向 file/shmem/mmap | 未提供 native allocation stack、allocator stats 或具体 C 扩展释放证据 | 方向级 |
| mmap/file/shmem | RssFile/RssShmem 净增长主导、maps 指向 file/shmem，或 memory_surface 指向 file/shmem/mmap | Private_Dirty/heap 能解释主要增长 | 方向级或 mixed |
| plateau/high-water | RSS 高位平台、peak-final 大、对象最终释放 | 谷值持续上移、retention 证据强 | 非 retained leak 或待观察 |
| short-window | 样本少、duration 短、`insufficient_window` | 后续长窗口仍增长 | inconclusive |
| scope mismatch | worker/cgroup/sibling 与目标 PID 不一致 | 已切到增长 PID 且证据对齐 | 只读定界，不下根因 |

G2 的目标不是列满表格，而是明确“为什么不是更可能的替代解释”。每个被排除的假设至少引用一条结构化证据。

## 4. 模式映射

把 `semantic` label 和 `retention` root_kind 映射到 `root-cause-patterns.md`：

- `global_container_growth` 或 `module_global:<name>` -> 全局容器无界增长。
- `unbounded_cache_growth` 或 `cache:*` -> 无界缓存；若是实例方法 cache，还要说明 cache key 保留 `self`。
- `global_registry_retains_bound_methods` -> 回调/监听器 registry 保留 bound method 和实例。
- `global_table_retains_closures` -> 闭包 cell 捕获 payload。
- `threading.local`、长期 worker 或 thread-local 语义 -> 线程局部状态泄漏。
- `unclosed_generators_retain_frames`、`pending_asyncio_tasks_retain_frames` -> frame locals 被 generator/task 保留。
- `gc.garbage`、cycle/finalizer 信号 -> 引用循环/finalizer。
- `weakref_finalize_callbacks_retained` -> `weakref.finalize` 回调误用。

若模式映射和 G1 对账冲突，以 G1 为准：小规模模式只能写次要问题或干扰项。

## 5. 置信度

- `confirmed`：G0/G1/G2 通过，并且 G3 counterfactual 或 G4 隔离复测通过。
- `strong`：G0/G1/G2 通过，semantic/retention/tracemalloc 一致，但 G3/G4 未执行。
- `weak`：只有单条 Python 证据、retention unknown、短窗口或静态可达性。
- `direction-only`：只读 PID、native/mmap/allocator、scope mismatch 或缺少 heap/retention。

禁止把 `readonly_insufficient`、`native_or_allocator_suspect`、`mmap_or_file_backed_growth`、`allocator_reuse_or_fragmentation_possible` 写成已确认 Python 根因。
