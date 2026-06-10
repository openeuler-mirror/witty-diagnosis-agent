# 验证门

验证门是报告前的填表规则。每道门都要写“输入证据、结果、缺口、报告措辞”，不能只写“已验证”。

| 门 | 输入 | 通过条件 | 失败回退 | 报告措辞 |
| --- | --- | --- | --- | --- |
| G0 目标范围和口径确认 | `discovery.json`、`live_process_snapshot.json`、`monitor_rss_pid.json` | PID、process tree、cgroup、worker、mapping 与当前目标一致 | 只做 scope 定界，切换 worker/cgroup 或补充范围 | “当前证据只能说明范围/口径问题” |
| G1 量化对账 | `object_growth.json`、`tracemalloc.json`、`correlation.json` | 主候选解释主要增长，或 correlation 给出方向级边界 | 回对象/分配/语义证据找更大来源 | “候选解释了主要增长”或“候选不足” |
| G2 竞争假设 | `evidence-analysis.md` 假设矩阵 | 相关替代假设均有支持/反证记录 | 保留多假设或降级置信度 | “已排除/尚未排除的替代解释” |
| G3 可达性 | `retention.json`、`reachability_*.json` | 反事实回收成功，或静态保留链充分且声明封顶 | 回保留链找其他路径 | “confirmed/partial/static-only” |
| G4 隔离复测 | 修复/禁用候选后的同 workload 结果 | 增长停止或速率显著下降 | 作为复测建议，不提升 confirmed | “未执行隔离复测” |
| G5 置信度 | G0-G4 汇总和 `confidence_cap` | 等级与证据强度一致 | 降到 weak 或 direction-only | “置信度和封顶原因” |

## G0 目标范围和口径确认

真实 PID 或线上只读场景必须先确认 PID、PPID、cmdline、exe、cwd、子进程、cgroup 与 mapping。`cgroup_growth_not_target`、`worker_skew_growth`、`process_tree_scope_required` 或 file/shmem flags 出现时，不能确认目标 PID 的 Python heap 根因。

## G1 量化对账

报告前必须读取 `correlation.json`。`python_heap_to_private_dirty_ratio` 或 `tracked_object_to_private_dirty_ratio` 足够高，并且有 semantic/retention 证据，才能写 Python retained leak likely。candidate coverage 低时写“候选不足以解释主要增长”，并把它放入 G2 干扰项。

## G2 竞争假设

至少考虑 Python retained、native/allocator、mmap/file/shmem、plateau/high-water、short-window、scope mismatch。每个被排除的假设至少引用一条结构化证据；无法排除时保留为未验证项。

## G3 可达性反事实

沙箱中可清空全局容器、cache 或 registry，然后 `gc.collect()` 并比较对象计数或 weakref 存活。生产环境不执行副作用，只做静态保留链论证，置信度封顶为 weak 或 strong static。

## G4 隔离复测

禁用候选逻辑、设置缓存上限、注销回调或修复生命周期后复跑相同 workload。没有 G4 时可以给 strong hypothesis，但不能把复杂场景写成 confirmed。

## G5 置信度

- `confirmed`：G0/G1/G2 通过，并且 G3 counterfactual 或 G4 隔离复测通过。
- `strong`：G0/G1/G2 通过，semantic/retention/tracemalloc 一致，但 G3/G4 未执行。
- `weak`：只有单条 Python 证据、retention unknown、短窗口或静态可达性。
- `direction-only`：只读 PID、native/mmap/allocator、scope mismatch 或缺少 heap/retention。
