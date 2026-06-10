# native / allocator / mmap 与 Python 堆背离路径

进入条件：

- RSS 或 Private_Dirty 持续增长。
- `object_growth.py` 未发现可解释的 Python 对象增长。
- `tracemalloc_probe.py` diff 远小于 RSS 净增长。
- `correlate_evidence.py` 输出 `native_or_allocator_suspect`、`mmap_or_file_backed_growth`、`mixed_growth` 或 `readonly_insufficient`。
- `live_process_snapshot.py` 或 `monitor_rss.py` 显示 RssFile、RssShmem、Private_Dirty、mapping/cgroup 口径与 Python heap 证据背离。

## 主路径

1. 先引用 `correlation.json` 的 `verdict`、`confidence_cap`、`missing_evidence`，说明当前是否能确认 Python retained leak。
2. 对账 `monitor_rss.py` 的 `rss_net_growth_bytes`、`private_dirty_net_growth_bytes`、`rss_anon/file/shmem`、`cgroup_memory_current_bytes` 和 `children_rss_bytes`。
3. 对账 `live_process_snapshot.py` 的 `memory_breakdown`、`mapping_summary`、`smaps_rollup`、`children_summary` 和 `cgroup_scope`。
4. 计算或引用 Python heap ratio：`tracemalloc net/current` 与 `Private_Dirty` 增长、`object_growth` tracked bytes 与 `Private_Dirty` 增长之间的比例。
5. 若 ratio 低且 Private_Dirty/RssAnon 增长明显，写 native/C 扩展/allocator 方向疑似。
6. 若 RssFile/RssShmem 或 file/shmem mapping 主导，写 mmap/file/shmem 方向疑似。
7. 若 RSS 高位平台但 tail 不再增长，写 allocator reuse、arena、cache warmup 或 high-water 方向，不确认 leak。

## 可选外部证据

Memray、gdb、allocator stats、BCC memleak 等只作为已有证据或单独审批后的采集建议，不作为本 skill 默认依赖，也不复制其代码。

- 若已有 memray capture/report，可用 `parse_memray.py` 解析或人工读取 outstanding/native allocation 线索。
- 若可复现且用户允许额外工具，才建议全生命周期 native allocation 采集；attach 只能覆盖 attach 之后的分配，不能证明历史增长。
- 若需要 C 栈符号，必须说明 debug symbols、权限、ptrace 风险和可能暂停进程的影响。

报告措辞应为“RSS/Private_Dirty 与 Python 堆证据背离，native/C 扩展、allocator 或 mmap/file/shmem 方向疑似”。除非已有 native allocator 栈、具体库、符号和未释放字节对账，不得写“已确认 native 根因”。
